//! Adapter for protocol writers that push chunks instead of implementing
//! `AsyncWrite`.
//!
//! The caller writes into an in-memory pipe; a spawned task drains it into the
//! protocol writer and finalizes it. `shutdown` waits for that finalization so
//! upload errors reach the caller instead of being lost with the task.

use std::future::Future;
use std::io;
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, DuplexStream, ReadBuf};

pub(crate) struct PipeWriter {
    tx: Option<DuplexStream>,
    result: Option<tokio::sync::oneshot::Receiver<Result<(), String>>>,
    done: bool,
}

impl AsyncWrite for PipeWriter {
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
                                Ok(Err(task_err)) => return Poll::Ready(Err(io::Error::other(task_err))),
                                Err(_) => return Poll::Ready(Err(io::Error::other("upload task ended unexpectedly"))),
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

impl Drop for PipeWriter {
    fn drop(&mut self) {
        // Dropping the pipe makes the upload task see EOF and finalize.
        self.tx = None;
    }
}

/// Spawn `upload`, handing it the read half of an in-memory pipe.
pub(crate) fn pipe_writer<F, Fut>(upload: F) -> Box<dyn AsyncWrite + Send + Unpin>
where
    F: FnOnce(DuplexStream) -> Fut + Send + 'static,
    Fut: Future<Output = Result<(), String>> + Send + 'static,
{
    let (tx, rx) = tokio::io::duplex(256 * 1024);
    let (done_tx, done_rx) = tokio::sync::oneshot::channel();
    tokio::spawn(async move {
        let _ = done_tx.send(upload(rx).await);
    });
    Box::new(PipeWriter {
        tx: Some(tx),
        result: Some(done_rx),
        done: false,
    })
}

/// Read side of a one-shot download pipe: the mirror of [`PipeWriter`].
///
/// The producer task pushes bytes into the pipe and returns a final
/// result. When the pipe reaches EOF the reader reports that result
/// first: an `Err` is delivered as a read error instead of a clean EOF,
/// so a transfer that failed halfway cannot masquerade as a complete
/// file to the caller's copy loop.
pub(crate) struct SignalingReader {
    rx: DuplexStream,
    result: Option<tokio::sync::oneshot::Receiver<Result<(), String>>>,
}

impl AsyncRead for SignalingReader {
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

/// Spawn `producer`, handing it the write half of an in-memory pipe.
pub(crate) fn signaling_reader<F, Fut>(producer: F) -> Box<dyn AsyncRead + Send + Unpin>
where
    F: FnOnce(DuplexStream) -> Fut + Send + 'static,
    Fut: Future<Output = Result<(), String>> + Send + 'static,
{
    let (tx, rx) = tokio::io::duplex(256 * 1024);
    let (done_tx, done_rx) = tokio::sync::oneshot::channel();
    tokio::spawn(async move {
        let _ = done_tx.send(producer(tx).await);
    });
    Box::new(SignalingReader {
        rx,
        result: Some(done_rx),
    })
}

/// Copy the pipe to `sink` until EOF.
pub(crate) async fn drain_pipe(
    rx: &mut DuplexStream,
    sink: &mut (impl AsyncWrite + Unpin),
) -> Result<(), String> {
    let mut buf = vec![0u8; 64 * 1024];
    loop {
        let n = rx.read(&mut buf).await.map_err(|e| e.to_string())?;
        if n == 0 {
            return Ok(());
        }
        sink.write_all(&buf[..n])
            .await
            .map_err(|e| e.to_string())?;
    }
}
