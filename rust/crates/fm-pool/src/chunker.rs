//! Streaming fixed-size chunk writer (`AsyncWrite`) with deduplication,
//! cross-domain 2-replica concurrent placement + automatic 3rd-node failover,
//! and streaming cross-chunk `Range` reader (`AsyncRead`) with transparent
//! replica failover and `FPC1` sub-chunk decryption.

use crate::crypto::{
    chunk_content_id, decrypt_subchunk_fpc1, encrypt_chunk_fpc1, fpc1_subchunk_plan, Fpc1Header,
    GCM_TAG_SIZE, FPC1_HEADER_SIZE,
};
use crate::error::{PoolError, PoolResult};
use crate::meta::{FileChunkRecord, WriteChunkInput};
use crate::scheduler::{rank_read_replicas, select_write_nodes, NodePlacementInfo, ReplicaLocation};
use crate::storage::blob_relpath;
use crate::PoolState;
use fm_core::{VfsPath, WriteMode};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::future::Future;
use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, DuplexStream, ReadBuf};

struct PoolPipeWriter {
    tx: Option<DuplexStream>,
    result: Option<tokio::sync::oneshot::Receiver<Result<(), String>>>,
    abort: Option<tokio::sync::oneshot::Sender<()>>,
    done: bool,
}

impl AsyncWrite for PoolPipeWriter {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        let this = self.get_mut();
        if let Some(rx) = this.result.as_mut() {
            if let Poll::Ready(res) = Pin::new(rx).poll(cx) {
                this.result = None;
                this.done = true;
                match res {
                    Ok(Ok(())) => {
                        return Poll::Ready(Err(io::Error::new(
                            io::ErrorKind::UnexpectedEof,
                            "upload task completed prematurely",
                        )));
                    }
                    Ok(Err(e)) => return Poll::Ready(Err(io::Error::other(e))),
                    Err(_) => {
                        return Poll::Ready(Err(io::Error::other(
                            "upload task ended unexpectedly",
                        )));
                    }
                }
            }
        }
        match this.tx.as_mut() {
            Some(tx) => match Pin::new(tx).poll_write(cx, buf) {
                Poll::Ready(Err(e)) if e.kind() == io::ErrorKind::BrokenPipe => {
                    if let Some(mut rx) = this.result.take() {
                        if let Poll::Ready(res) = Pin::new(&mut rx).poll(cx) {
                            this.done = true;
                            match res {
                                Ok(Err(err_msg)) => {
                                    return Poll::Ready(Err(io::Error::other(err_msg)))
                                }
                                Err(_) => {
                                    return Poll::Ready(Err(io::Error::other(
                                        "upload task ended unexpectedly",
                                    )))
                                }
                                _ => {}
                            }
                        } else {
                            this.result = Some(rx);
                        }
                    }
                    Poll::Ready(Err(e))
                }
                other => other,
            },
            None => Poll::Ready(Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "writer already shut down",
            ))),
        }
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if let Some(rx) = this.result.as_mut() {
            if let Poll::Ready(res) = Pin::new(rx).poll(cx) {
                this.result = None;
                this.done = true;
                match res {
                    Ok(Ok(())) => {}
                    Ok(Err(e)) => return Poll::Ready(Err(io::Error::other(e))),
                    Err(_) => {
                        return Poll::Ready(Err(io::Error::other(
                            "upload task ended unexpectedly",
                        )));
                    }
                }
            }
        }
        match this.tx.as_mut() {
            Some(tx) => Pin::new(tx).poll_flush(cx),
            None => Poll::Ready(Ok(())),
        }
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if this.done {
            return Poll::Ready(Ok(()));
        }
        if let Some(tx) = this.tx.as_mut() {
            match Pin::new(tx).poll_shutdown(cx) {
                Poll::Ready(_) => {
                    this.tx = None;
                }
                Poll::Pending => return Poll::Pending,
            }
        }
        match this.result.as_mut() {
            Some(rx) => match Pin::new(rx).poll(cx) {
                Poll::Ready(Ok(Ok(()))) => {
                    this.done = true;
                    Poll::Ready(Ok(()))
                }
                Poll::Ready(Ok(Err(e))) => {
                    this.done = true;
                    Poll::Ready(Err(io::Error::other(e)))
                }
                Poll::Ready(Err(_)) => {
                    this.done = true;
                    Poll::Ready(Err(io::Error::other("upload task ended unexpectedly")))
                }
                Poll::Pending => Poll::Pending,
            },
            None => {
                this.done = true;
                Poll::Ready(Ok(()))
            }
        }
    }
}

impl Drop for PoolPipeWriter {
    fn drop(&mut self) {
        self.tx = None;
        if !self.done {
            if let Some(abort) = self.abort.take() {
                let _ = abort.send(());
            }
        }
    }
}

struct PoolSignalingReader {
    rx: DuplexStream,
    result: Option<tokio::sync::oneshot::Receiver<Result<(), String>>>,
}

impl AsyncRead for PoolSignalingReader {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        match Pin::new(&mut this.rx).poll_read(cx, buf) {
            Poll::Ready(Ok(())) if buf.filled().is_empty() => match this.result.take() {
                Some(mut result_rx) => match Pin::new(&mut result_rx).poll(cx) {
                    Poll::Ready(Ok(Ok(()))) => Poll::Ready(Ok(())),
                    Poll::Ready(Ok(Err(e))) => Poll::Ready(Err(io::Error::other(e))),
                    Poll::Ready(Err(_)) => Poll::Ready(Err(io::Error::other(
                        "download task ended unexpectedly",
                    ))),
                    Poll::Pending => {
                        this.result = Some(result_rx);
                        Poll::Pending
                    }
                },
                None => Poll::Ready(Ok(())),
            },
            other => other,
        }
    }
}

fn spawn_signaling_reader<F, Fut>(producer: F) -> Box<dyn AsyncRead + Send + Unpin>
where
    F: FnOnce(DuplexStream) -> Fut + Send + 'static,
    Fut: Future<Output = Result<(), String>> + Send + 'static,
{
    let (tx, rx) = tokio::io::duplex(256 * 1024);
    let (done_tx, done_rx) = tokio::sync::oneshot::channel();
    tokio::spawn(async move {
        let _ = done_tx.send(producer(tx).await);
    });
    Box::new(PoolSignalingReader {
        rx,
        result: Some(done_rx),
    })
}

pub async fn open_pool_writer(
    state: Arc<PoolState>,
    path: &VfsPath,
    mode: WriteMode,
) -> PoolResult<Box<dyn AsyncWrite + Send + Unpin>> {
    let existing = match state.meta.stat(path) {
        Ok(e) => Some(e),
        Err(PoolError::PathNotFound(_)) => None,
        Err(e) => return Err(e),
    };

    if let Some(ref entry) = existing {
        if entry.kind == "dir" {
            return Err(PoolError::AlreadyExists(format!(
                "destination is a directory: {path}"
            )));
        }
        if mode == WriteMode::Create {
            return Err(PoolError::AlreadyExists(path.to_slash_string()));
        }
    }

    let nodes = state.meta.list_nodes()?;
    let writable_count = nodes
        .iter()
        .filter(|n| n.role.is_writable() && !state.health.is_circuit_open(&n.node_id))
        .count();
    if writable_count == 0 {
        return Err(PoolError::NoWritableNodes);
    }

    let existing_bytes_for_append = if mode == WriteMode::Append {
        if let Some(ref entry) = existing {
            if entry.size_bytes > 0 {
                let mut r = open_pool_reader(Arc::clone(&state), path, 0, None).await?;
                let mut existing_buf = Vec::with_capacity(entry.size_bytes.min(16 * 1024 * 1024) as usize);
                r.read_to_end(&mut existing_buf).await?;
                Some(existing_buf)
            } else {
                None
            }
        } else {
            None
        }
    } else {
        None
    };

    let chunk_size = state.chunk_size() as usize;
    let target_path = path.clone();
    let create_only = mode == WriteMode::Create;
    let (tx, mut rx) = tokio::io::duplex(256 * 1024);
    let (done_tx, done_rx) = tokio::sync::oneshot::channel();
    let (abort_tx, mut abort_rx) = tokio::sync::oneshot::channel();

    tokio::spawn(async move {
        let upload_fut = async {
            let mut buffer: Vec<u8> = existing_bytes_for_append.unwrap_or_default();
            let mut chunks: Vec<WriteChunkInput> = Vec::new();
            let mut total_plain: u64 = 0;
            let mut whole_hasher = Sha256::new();
            let mut chunk_index: u32 = 0;

            // If Append pre-filled more than chunk_size bytes, flush full chunks first.
            while buffer.len() >= chunk_size {
                let chunk_bytes: Vec<u8> = buffer.drain(..chunk_size).collect();
                total_plain = total_plain.saturating_add(chunk_bytes.len() as u64);
                whole_hasher.update(&chunk_bytes);
                let chunk_input = flush_one_chunk(&state, chunk_index, &chunk_bytes)
                    .await
                    .map_err(|e| e.to_string())?;
                chunks.push(chunk_input);
                chunk_index = chunk_index.saturating_add(1);
            }

            let mut scratch = vec![0u8; 64 * 1024];
            loop {
                let n = rx.read(&mut scratch).await.map_err(|e| e.to_string())?;
                if n == 0 {
                    break;
                }
                let mut offset = 0usize;
                while offset < n {
                    let take = (chunk_size - buffer.len()).min(n - offset);
                    buffer.extend_from_slice(&scratch[offset..offset + take]);
                    offset += take;
                    if buffer.len() == chunk_size {
                        total_plain = total_plain.saturating_add(buffer.len() as u64);
                        whole_hasher.update(&buffer);
                        let chunk_input = flush_one_chunk(&state, chunk_index, &buffer)
                            .await
                            .map_err(|e| e.to_string())?;
                        chunks.push(chunk_input);
                        chunk_index = chunk_index.saturating_add(1);
                        buffer.clear();
                    }
                }
            }

            // Flush trailing bytes (or a single 0-byte chunk? Keep 0-byte file as 0 chunks).
            if !buffer.is_empty() {
                total_plain = total_plain.saturating_add(buffer.len() as u64);
                whole_hasher.update(&buffer);
                let chunk_input = flush_one_chunk(&state, chunk_index, &buffer)
                    .await
                    .map_err(|e| e.to_string())?;
                chunks.push(chunk_input);
            }

            let content_hash = hex::encode(whole_hasher.finalize());
            state
                .meta
                .commit_file_write(
                    &target_path,
                    total_plain,
                    chunk_size as u32,
                    Some(&content_hash),
                    &chunks,
                    create_only,
                )
                .map_err(|e| e.to_string())?;
            state.schedule_debounced_sync();
            Ok::<(), String>(())
        };

        let res = tokio::select! {
            r = upload_fut => r,
            _ = &mut abort_rx => Err("upload aborted".to_string()),
        };
        let _ = done_tx.send(res);
    });

    Ok(Box::new(PoolPipeWriter {
        tx: Some(tx),
        result: Some(done_rx),
        abort: Some(abort_tx),
        done: false,
    }))
}

async fn flush_one_chunk(
    state: &PoolState,
    chunk_index: u32,
    plaintext: &[u8],
) -> PoolResult<WriteChunkInput> {
    let crypto_guard = state.crypto();
    let crypto_ref = crypto_guard.as_ref();
    let chunk_hash = chunk_content_id(crypto_ref, plaintext)?;

    let existing_replicas = state.meta.get_ok_replicas_for_chunk(&chunk_hash)?;
    let target_replicas = state.replication_factor();
    let existing_nodes: HashSet<String> = existing_replicas
        .iter()
        .map(|r| r.node_id.clone())
        .collect();

    // Fast deduplication when enough healthy replicas already exist.
    if existing_replicas.len() >= target_replicas {
        let existing_stored = state
            .meta
            .list_nodes()
            .ok()
            .and_then(|_| existing_replicas.first())
            .map(|_| {
                if crypto_ref.is_some() {
                    let subs = if plaintext.is_empty() {
                        1
                    } else {
                        ((plaintext.len() - 1) / crate::crypto::FPC1_SUB_CHUNK_SIZE) + 1
                    };
                    (FPC1_HEADER_SIZE + plaintext.len() + subs * GCM_TAG_SIZE) as u64
                } else {
                    plaintext.len() as u64
                }
            })
            .unwrap_or(plaintext.len() as u64);
        return Ok(WriteChunkInput {
            chunk_index,
            chunk_hash,
            plain_size: plaintext.len() as u64,
            stored_size: existing_stored,
            encrypted: crypto_ref.is_some(),
            new_replicas: Vec::new(),
        });
    }

    let (payload, encrypted): (Arc<Vec<u8>>, bool) = match crypto_ref {
        Some(c) => (Arc::new(encrypt_chunk_fpc1(c, &chunk_hash, plaintext)?), true),
        None => (Arc::new(plaintext.to_vec()), false),
    };
    let stored_size = payload.len() as u64;
    let relpath = blob_relpath(&chunk_hash);

    let needed = target_replicas.saturating_sub(existing_replicas.len());
    let all_nodes = state.meta.list_nodes()?;
    let existing_domains: HashSet<String> = existing_replicas
        .iter()
        .filter_map(|rep| {
            all_nodes
                .iter()
                .find(|n| n.node_id == rep.node_id)
                .map(|n| n.failure_domain.clone())
        })
        .collect();

    let picked = select_write_nodes(
        &all_nodes,
        &state.health,
        stored_size,
        needed,
        &existing_nodes,
        &existing_domains,
    );

    if picked.is_empty() {
        if !existing_replicas.is_empty() {
            return Ok(WriteChunkInput {
                chunk_index,
                chunk_hash,
                plain_size: plaintext.len() as u64,
                stored_size,
                encrypted,
                new_replicas: Vec::new(),
            });
        }
        return Err(PoolError::NoWritableNodes);
    }

    let mut written_replicas: Vec<(String, String)> = Vec::new();
    let mut attempted_ids: HashSet<String> = existing_nodes;
    for n in &picked {
        attempted_ids.insert(n.node_id.clone());
    }
    let mut failures: Vec<String> = Vec::new();

    let write_futs = picked
        .iter()
        .map(|node| state.io.write_bytes(node, &relpath, &payload));
    let write_results = futures_util::future::join_all(write_futs).await;
    for (node, res) in picked.iter().zip(write_results) {
        match res {
            Ok(()) => written_replicas.push((node.node_id.clone(), relpath.clone())),
            Err(e) => failures.push(format!("{}: {e}", node.node_id)),
        }
    }

    // Backfill up to `needed` if any initial target failed, selecting a 3rd node.
    while written_replicas.len() < needed {
        let mut avoid_domains = existing_domains.clone();
        for (wid, _) in &written_replicas {
            if let Some(node) = all_nodes.iter().find(|n| &n.node_id == wid) {
                avoid_domains.insert(node.failure_domain.clone());
            }
        }
        let next = select_write_nodes(
            &all_nodes,
            &state.health,
            stored_size,
            1,
            &attempted_ids,
            &avoid_domains,
        );
        let Some(cand) = next.into_iter().next() else {
            break;
        };
        attempted_ids.insert(cand.node_id.clone());
        match state.io.write_bytes(&cand, &relpath, &payload).await {
            Ok(()) => written_replicas.push((cand.node_id, relpath.clone())),
            Err(e) => failures.push(format!("{}: {e}", cand.node_id)),
        }
    }

    if written_replicas.is_empty() && existing_replicas.is_empty() {
        return Err(PoolError::AllReplicasFailed {
            chunk_hash,
            details: failures.join("; "),
        });
    }

    Ok(WriteChunkInput {
        chunk_index,
        chunk_hash,
        plain_size: plaintext.len() as u64,
        stored_size,
        encrypted,
        new_replicas: written_replicas,
    })
}

#[derive(Debug, Clone)]
struct ChunkReadSlice {
    chunk: FileChunkRecord,
    /// Offset inside the plaintext chunk.
    in_chunk_offset: u64,
    /// Number of plaintext bytes to emit from this chunk.
    emit_len: u64,
}

pub async fn open_pool_reader(
    state: Arc<PoolState>,
    path: &VfsPath,
    offset: u64,
    length: Option<u64>,
) -> PoolResult<Box<dyn AsyncRead + Send + Unpin>> {
    let entry = state.meta.stat(path)?;
    if entry.kind == "dir" {
        return Err(PoolError::InvalidPath(format!(
            "cannot open directory for reading: {path}"
        )));
    }
    if entry.size_bytes == 0 || offset >= entry.size_bytes {
        return Ok(Box::new(tokio::io::empty()));
    }
    let end = match length {
        Some(len) => offset.saturating_add(len).min(entry.size_bytes),
        None => entry.size_bytes,
    };
    if end <= offset {
        return Ok(Box::new(tokio::io::empty()));
    }

    let chunks = state.meta.get_file_chunks(entry.id)?;
    let mut slices: Vec<ChunkReadSlice> = Vec::new();
    let mut chunk_start = 0u64;
    for ch in chunks {
        let chunk_end = chunk_start.saturating_add(ch.plain_size);
        if chunk_end > offset && chunk_start < end {
            let slice_start = offset.saturating_sub(chunk_start);
            let slice_end = (end - chunk_start).min(ch.plain_size);
            if slice_end > slice_start {
                slices.push(ChunkReadSlice {
                    chunk: ch,
                    in_chunk_offset: slice_start,
                    emit_len: slice_end - slice_start,
                });
            }
        }
        chunk_start = chunk_end;
        if chunk_start >= end {
            break;
        }
    }

    if slices.is_empty() {
        return Ok(Box::new(tokio::io::empty()));
    }

    Ok(spawn_signaling_reader(move |mut tx| async move {
        use tokio::io::AsyncWriteExt;
        for slice in slices {
            stream_chunk_slice(&state, &slice, &mut tx)
                .await
                .map_err(|e| e.to_string())?;
        }
        tx.shutdown().await.map_err(|e| e.to_string())?;
        Ok(())
    }))
}

async fn stream_chunk_slice(
    state: &PoolState,
    slice: &ChunkReadSlice,
    tx: &mut DuplexStream,
) -> PoolResult<()> {
    let replicas = state.meta.get_chunk_replicas(&slice.chunk.chunk_hash)?;
    let nodes = state.meta.list_nodes()?;
    let ranked = rank_read_replicas(&replicas, &nodes, &state.health);

    if ranked.is_empty() {
        return Err(PoolError::AllReplicasFailed {
            chunk_hash: slice.chunk.chunk_hash.clone(),
            details: "no available online replicas".to_string(),
        });
    }

    if !slice.chunk.encrypted {
        stream_plaintext_slice(state, slice, &ranked, tx).await
    } else {
        stream_encrypted_slice(state, slice, &ranked, tx).await
    }
}

async fn stream_plaintext_slice(
    state: &PoolState,
    slice: &ChunkReadSlice,
    ranked: &[(ReplicaLocation, NodePlacementInfo)],
    tx: &mut DuplexStream,
) -> PoolResult<()> {
    use tokio::io::AsyncWriteExt;

    let mut done_in_slice: u64 = 0;
    let total_emit = slice.emit_len;
    let mut errors: Vec<String> = Vec::new();
    let mut buf = vec![0u8; 64 * 1024];

    for (rep, node) in ranked {
        if done_in_slice >= total_emit {
            break;
        }
        let cur_offset = slice.in_chunk_offset + done_in_slice;
        let remaining = total_emit - done_in_slice;

        let mut reader = match state
            .io
            .open_read_range_stream(node, &rep.remote_relpath, cur_offset, Some(remaining))
            .await
        {
            Ok(r) => r,
            Err(e) => {
                errors.push(format!("{}: {e}", node.node_id));
                continue;
            }
        };

        let mut replica_failed = false;
        while done_in_slice < total_emit {
            let want = (total_emit - done_in_slice).min(buf.len() as u64) as usize;
            let read_res =
                tokio::time::timeout(state.io.read_timeout(), reader.read(&mut buf[..want])).await;
            match read_res {
                Ok(Ok(0)) => {
                    if done_in_slice < total_emit {
                        state.io.record_failure(&node.node_id);
                        errors.push(format!(
                            "{}: premature EOF at {}/{}",
                            node.node_id, done_in_slice, total_emit
                        ));
                        replica_failed = true;
                    }
                    break;
                }
                Ok(Ok(n)) => {
                    tx.write_all(&buf[..n]).await?;
                    done_in_slice += n as u64;
                }
                Ok(Err(e)) => {
                    state.io.record_failure(&node.node_id);
                    errors.push(format!("{}: {e}", node.node_id));
                    replica_failed = true;
                    break;
                }
                Err(_) => {
                    state.io.record_failure(&node.node_id);
                    errors.push(format!("{}: read timed out", node.node_id));
                    replica_failed = true;
                    break;
                }
            }
        }
        if !replica_failed && done_in_slice >= total_emit {
            return Ok(());
        }
    }

    if done_in_slice >= total_emit {
        Ok(())
    } else {
        Err(PoolError::AllReplicasFailed {
            chunk_hash: slice.chunk.chunk_hash.clone(),
            details: errors.join("; "),
        })
    }
}

async fn stream_encrypted_slice(
    state: &PoolState,
    slice: &ChunkReadSlice,
    ranked: &[(ReplicaLocation, NodePlacementInfo)],
    tx: &mut DuplexStream,
) -> PoolResult<()> {
    use tokio::io::AsyncWriteExt;

    let crypto = state.crypto().ok_or_else(|| {
        PoolError::Crypto(format!(
            "chunk {} is encrypted, but pool encryption key is not unlocked",
            slice.chunk.chunk_hash
        ))
    })?;

    let mut done_in_slice: u64 = 0;
    let total_emit = slice.emit_len;
    let mut errors: Vec<String> = Vec::new();

    for (rep, node) in ranked {
        if done_in_slice >= total_emit {
            break;
        }
        let cur_offset = slice.in_chunk_offset + done_in_slice;
        let remaining = total_emit - done_in_slice;

        let header_bytes = match state
            .io
            .read_exact_range(node, &rep.remote_relpath, 0, FPC1_HEADER_SIZE as u64)
            .await
        {
            Ok(b) => b,
            Err(e) => {
                errors.push(format!("{}: header read failed: {e}", node.node_id));
                continue;
            }
        };
        let header = match Fpc1Header::decode(&header_bytes) {
            Ok(h) => h,
            Err(e) => {
                let _ = state
                    .meta
                    .mark_replica_status(&slice.chunk.chunk_hash, &node.node_id, "suspect");
                errors.push(format!("{}: invalid FPC1 header: {e}", node.node_id));
                continue;
            }
        };
        if header.plain_len != slice.chunk.plain_size {
            let _ = state
                .meta
                .mark_replica_status(&slice.chunk.chunk_hash, &node.node_id, "suspect");
            errors.push(format!(
                "{}: plain_len mismatch ({} != {})",
                node.node_id, header.plain_len, slice.chunk.plain_size
            ));
            continue;
        }

        let Some(plan) = fpc1_subchunk_plan(&header, cur_offset, remaining) else {
            return Ok(());
        };
        let subkey = crypto.derive_chunk_key(&header.chunk_salt)?;

        let mut reader = match state
            .io
            .open_read_range_stream(
                node,
                &rep.remote_relpath,
                plan.physical_offset,
                Some(plan.physical_len),
            )
            .await
        {
            Ok(r) => r,
            Err(e) => {
                errors.push(format!("{}: range stream failed: {e}", node.node_id));
                continue;
            }
        };

        let cs = header.sub_chunk_size as u64;
        let total_subs = header.total_sub_chunks();
        let mut ct_buf = vec![0u8; header.sub_chunk_size as usize + GCM_TAG_SIZE];
        let mut replica_failed = false;

        for sub_idx in plan.start_sub..=plan.end_sub {
            let is_final = sub_idx + 1 == total_subs;
            let plain_sub_len = if is_final {
                (header.plain_len - sub_idx * cs) as usize
            } else {
                cs as usize
            };
            let ct_len = plain_sub_len + GCM_TAG_SIZE;

            let read_res = tokio::time::timeout(
                state.io.read_timeout(),
                reader.read_exact(&mut ct_buf[..ct_len]),
            )
            .await;

            match read_res {
                Ok(Ok(_)) => {}
                Ok(Err(e)) => {
                    state.io.record_failure(&node.node_id);
                    errors.push(format!("{}: subchunk read error: {e}", node.node_id));
                    replica_failed = true;
                    break;
                }
                Err(_) => {
                    state.io.record_failure(&node.node_id);
                    errors.push(format!("{}: subchunk read timeout", node.node_id));
                    replica_failed = true;
                    break;
                }
            }

            let pt = match decrypt_subchunk_fpc1(
                &crypto,
                &header,
                &subkey,
                &slice.chunk.chunk_hash,
                sub_idx,
                &ct_buf[..ct_len],
            ) {
                Ok(p) => p,
                Err(e) => {
                    let _ = state.meta.mark_replica_status(
                        &slice.chunk.chunk_hash,
                        &node.node_id,
                        "suspect",
                    );
                    errors.push(format!("{}: {e}", node.node_id));
                    replica_failed = true;
                    break;
                }
            };

            let sub_start = sub_idx * cs;
            let slice_start = cur_offset.saturating_sub(sub_start) as usize;
            let slice_end = (cur_offset + remaining - sub_start).min(plain_sub_len as u64) as usize;
            if slice_end > slice_start {
                let bytes = &pt[slice_start..slice_end];
                tx.write_all(bytes).await?;
                done_in_slice += bytes.len() as u64;
            }
        }

        if !replica_failed && done_in_slice >= total_emit {
            return Ok(());
        }
    }

    if done_in_slice >= total_emit {
        Ok(())
    } else {
        Err(PoolError::AllReplicasFailed {
            chunk_hash: slice.chunk.chunk_hash.clone(),
            details: errors.join("; "),
        })
    }
}
