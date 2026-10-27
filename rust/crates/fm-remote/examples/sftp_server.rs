use std::collections::HashMap;
use std::net::SocketAddr;
use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;
use russh::server::{Auth, ChannelOpenHandle, Msg, Server as _, Session};
use russh::{Channel, ChannelId};
use tokio::sync::Mutex;

const TEST_KEY: &str = "-----BEGIN OPENSSH PRIVATE KEY-----\n\
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW\n\
QyNTUxOQAAACDr2KMPUPhHH0n3JMt2fBV1JpLILJ6kXhPOzsnsg5haxQAAAJiJSqWriUql\n\
qwAAAAtzc2gtZWQyNTUxOQAAACDr2KMPUPhHH0n3JMt2fBV1JpLILJ6kXhPOzsnsg5haxQ\n\
AAAECP6u6+mfAE3YKjYnvre8cwIyo1lqKfPm9cWFTyPdqJfuvYow9Q+EcfSfcky3Z8FXUm\n\
ksgsnqReE87OyeyDmFrFAAAAEXRoQHRocy1pTWFjLmxvY2FsAQIDBA==\n\
-----END OPENSSH PRIVATE KEY-----\n";

#[derive(Clone)]
struct SftpServer;

impl russh::server::Server for SftpServer {
    type Handler = SshHandler;

    fn new_client(&mut self, _: Option<SocketAddr>) -> Self::Handler {
        SshHandler {
            channels: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

struct SshHandler {
    channels: Arc<Mutex<HashMap<ChannelId, Channel<Msg>>>>,
}

impl russh::server::Handler for SshHandler {
    type Error = russh::Error;

    async fn auth_password(&mut self, _user: &str, _password: &str) -> Result<Auth, Self::Error> {
        Ok(Auth::Accept)
    }

    async fn auth_publickey(
        &mut self,
        _user: &str,
        _public_key: &russh::keys::PublicKey,
    ) -> Result<Auth, Self::Error> {
        Ok(Auth::Accept)
    }

    async fn channel_open_session(
        &mut self,
        channel: Channel<Msg>,
        reply: ChannelOpenHandle,
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        self.channels.lock().await.insert(channel.id(), channel);
        reply.accept().await;
        Ok(())
    }

    async fn subsystem_request(
        &mut self,
        channel_id: ChannelId,
        name: &str,
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        if name == "sftp" {
            let channel = self.channels.lock().await.remove(&channel_id);
            if let Some(channel) = channel {
                session.channel_success(channel_id)?;
                tokio::spawn(async move {
                    let mut child = match tokio::process::Command::new("/usr/libexec/sftp-server")
                        .stdin(Stdio::piped())
                        .stdout(Stdio::piped())
                        .stderr(Stdio::null())
                        .spawn()
                    {
                        Ok(c) => c,
                        Err(e) => {
                            eprintln!("failed to spawn sftp-server: {e}");
                            return;
                        }
                    };

                    let child_in = child.stdin.take().expect("stdin");
                    let child_out = child.stdout.take().expect("stdout");
                    let channel_stream = channel.into_stream();
                    let (mut ch_read, mut ch_write) = tokio::io::split(channel_stream);

                    let mut child_in_sink = child_in;
                    let mut child_out_stream = child_out;

                    let t1 = tokio::io::copy(&mut ch_read, &mut child_in_sink);
                    let t2 = tokio::io::copy(&mut child_out_stream, &mut ch_write);
                    let _ = tokio::join!(t1, t2);
                    let _ = child.wait().await;
                });
                return Ok(());
            }
        }
        session.channel_failure(channel_id)?;
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let port: u16 = std::env::var("SFTP_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(2222);

    let key = russh::keys::decode_secret_key(TEST_KEY, None)?;

    let config = russh::server::Config {
        auth_rejection_time: Duration::from_millis(10),
        auth_rejection_time_initial: Some(Duration::from_millis(0)),
        keys: vec![key],
        ..Default::default()
    };

    println!("SFTP server listening on 127.0.0.1:{}", port);
    let mut server = SftpServer;
    server
        .run_on_address(Arc::new(config), ("127.0.0.1", port))
        .await?;
    Ok(())
}
