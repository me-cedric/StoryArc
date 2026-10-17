//! The SMB 1 probe (design.md, Decision 7; `network-share`, *SMB 1 only server*).
//!
//! Neither SMB crate speaks SMB 1, so neither can say a server speaks nothing else. After a
//! handshake fails, the core asks the question itself: one SMB 1 `NEGOTIATE` offering only
//! `NT LM 0.12`, the dialect every SMB 1 server takes. Measured on Samba 4.24.7 (the spike,
//! `docs/delivery/desktop-spike-smb.md`): a server that speaks SMB 1 answers with word count
//! 17 and dialect index 0; a server that speaks SMB 2 or later answers with word count 1 and
//! dialect index `0xFFFF`, "no dialect in common". Only the first is reported as SMB 1 only,
//! so a server that failed for some other reason is never sent to change a setting it has.
//!
//! The probe never authenticates and never continues an SMB 1 session: it reads one reply and
//! closes the socket.

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::time::Duration;

/// The SMB 1 header's protocol signature, `\xFFSMB`.
const SMB1_SIGNATURE: [u8; 4] = [0xFF, b'S', b'M', b'B'];
/// `SMB_COM_NEGOTIATE`.
const NEGOTIATE: u8 = 0x72;
/// The one dialect offered.
const NT_LM: &[u8] = b"\x02NT LM 0.12\x00";
/// Bytes of the SMB 1 header.
const HEADER: usize = 32;
/// The most of a reply the probe reads. An NT LM negotiate reply is about 160 bytes.
const MOST: usize = 1024;

/// The SMB 1 `NEGOTIATE` request, with its four-byte direct-TCP length prefix.
pub(crate) fn request() -> Vec<u8> {
    let mut message = Vec::with_capacity(HEADER + 3 + NT_LM.len());
    message.extend_from_slice(&SMB1_SIGNATURE);
    message.push(NEGOTIATE);
    message.extend_from_slice(&[0; 4]); // status
    message.push(0x18); // flags: canonical paths, case insensitive
    message.extend_from_slice(&0xC853_u16.to_le_bytes()); // flags2: unicode, NT status, long names
    message.extend_from_slice(&[0; 12]); // PID high, security features, reserved
    message.extend_from_slice(&[0; 2]); // TID
    message.extend_from_slice(&0xFEFF_u16.to_le_bytes()); // PID
    message.extend_from_slice(&[0; 4]); // UID, MID
    message.push(0); // word count
    message.extend_from_slice(&(NT_LM.len() as u16).to_le_bytes());
    message.extend_from_slice(NT_LM);
    let mut framed = (message.len() as u32).to_be_bytes().to_vec();
    framed.extend_from_slice(&message);
    framed
}

/// Whether `reply` (without its length prefix) is an SMB 1 server accepting SMB 1.
pub(crate) fn speaks_only_smb1(reply: &[u8]) -> bool {
    if reply.len() < HEADER + 3 || reply[..4] != SMB1_SIGNATURE || reply[4] != NEGOTIATE {
        return false;
    }
    let status = u32::from_le_bytes([reply[5], reply[6], reply[7], reply[8]]);
    let word_count = reply[HEADER];
    let dialect = u16::from_le_bytes([reply[HEADER + 1], reply[HEADER + 2]]);
    status == 0 && word_count == 17 && dialect == 0
}

/// Asks `host:port` whether it speaks SMB 1 and accepted it. `false` on every failure: a probe
/// that could not finish has learned nothing, and nothing is claimed.
pub fn is_smb1_only(host: &str, port: u16, limit: Duration) -> bool {
    negotiate_reply(host, port, limit).is_some_and(|reply| speaks_only_smb1(&reply))
}

/// Whether an SMB server of any version answers at `host:port` within `limit`.
///
/// Stronger than an open socket, on purpose: `AGENTS.md` section 7 records a suite that ran
/// against the wrong server because a socket on its port answered, and a container proxy
/// accepts a connection even when the server behind it has stopped. Only a negotiate reply
/// carrying an SMB signature counts.
pub fn answers_smb(host: &str, port: u16, limit: Duration) -> bool {
    negotiate_reply(host, port, limit).is_some_and(|reply| {
        reply.len() >= 4 && (reply[..4] == SMB1_SIGNATURE || reply[..4] == *b"\xFESMB")
    })
}

/// The reply to one SMB 1 negotiate, without its length prefix, or `None` on any failure.
fn negotiate_reply(host: &str, port: u16, limit: Duration) -> Option<Vec<u8>> {
    let address = resolve(host, port)?;
    let mut stream = TcpStream::connect_timeout(&address, limit).ok()?;
    stream.set_read_timeout(Some(limit)).ok()?;
    stream.set_write_timeout(Some(limit)).ok()?;
    stream.write_all(&request()).ok()?;
    let mut prefix = [0; 4];
    stream.read_exact(&mut prefix).ok()?;
    let length = (u32::from_be_bytes(prefix) as usize).min(MOST);
    let mut reply = vec![0; length];
    stream.read_exact(&mut reply).ok()?;
    Some(reply)
}

fn resolve(host: &str, port: u16) -> Option<SocketAddr> {
    (host, port).to_socket_addrs().ok()?.next()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;

    /// The SMB 1 reply header, then `words` words and no bytes.
    fn reply(word_count: u8, dialect: u16, status: u32) -> Vec<u8> {
        let mut message = SMB1_SIGNATURE.to_vec();
        message.push(NEGOTIATE);
        message.extend_from_slice(&status.to_le_bytes());
        message.resize(HEADER, 0);
        message.push(word_count);
        message.extend_from_slice(&dialect.to_le_bytes());
        message.resize(HEADER + 1 + usize::from(word_count) * 2 + 2, 0);
        message
    }

    /// A server on an ephemeral port that answers one connection with `answer`.
    fn fake(answer: Vec<u8>) -> u16 {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            let mut prefix = [0; 4];
            socket.read_exact(&mut prefix).unwrap();
            let mut request = vec![0; u32::from_be_bytes(prefix) as usize];
            socket.read_exact(&mut request).unwrap();
            assert_eq!(
                &request[..5],
                b"\xFFSMBr",
                "the probe sends an SMB 1 negotiate"
            );
            let mut framed = (answer.len() as u32).to_be_bytes().to_vec();
            framed.extend_from_slice(&answer);
            socket.write_all(&framed).unwrap();
        });
        port
    }

    #[test]
    fn the_request_offers_only_nt_lm_and_carries_its_length() {
        let framed = request();
        let length = u32::from_be_bytes(framed[..4].try_into().unwrap()) as usize;
        assert_eq!(length, framed.len() - 4);
        assert_eq!(&framed[4..8], &SMB1_SIGNATURE);
        assert!(framed.ends_with(b"\x02NT LM 0.12\x00"));
    }

    #[test]
    fn an_smb1_server_that_picks_nt_lm_is_smb1_only() {
        assert!(speaks_only_smb1(&reply(17, 0, 0)));
        let port = fake(reply(17, 0, 0));
        assert!(is_smb1_only("127.0.0.1", port, Duration::from_secs(2)));
    }

    #[test]
    fn an_smb2_server_answering_no_dialect_is_not() {
        assert!(!speaks_only_smb1(&reply(1, 0xFFFF, 0)));
        let port = fake(reply(1, 0xFFFF, 0));
        assert!(!is_smb1_only("127.0.0.1", port, Duration::from_secs(2)));
        let port = fake(reply(1, 0xFFFF, 0));
        assert!(answers_smb("127.0.0.1", port, Duration::from_secs(2)));
    }

    #[test]
    fn a_socket_that_accepts_and_never_answers_is_not_an_smb_server() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let held = std::thread::spawn(move || {
            let (socket, _) = listener.accept().unwrap();
            std::thread::sleep(Duration::from_millis(600));
            drop(socket);
        });
        assert!(!answers_smb("127.0.0.1", port, Duration::from_millis(300)));
        held.join().unwrap();
    }

    #[test]
    fn an_smb2_reply_an_error_and_a_short_reply_are_not() {
        let mut smb2 = reply(17, 0, 0);
        smb2[0] = 0xFE;
        assert!(!speaks_only_smb1(&smb2));
        assert!(!speaks_only_smb1(&reply(17, 0, 0xC000_0001)));
        assert!(!speaks_only_smb1(&[0xFF, b'S', b'M', b'B']));
    }

    #[test]
    fn nothing_listening_is_not_a_claim() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        assert!(!is_smb1_only("127.0.0.1", port, Duration::from_millis(500)));
    }
}
