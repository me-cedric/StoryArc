//! The failures `network-share` names, read out of what the `smb` crate reports.
//!
//! *Adding a share*: the app reports success or the specific failure, "host unreachable,
//! share not found, authentication rejected, or protocol unsupported". A reader who typed the
//! wrong password and a reader whose NAS is asleep need different sentences, and one error
//! type does not tell them apart. The NT status numbers are the ones StoryArcKit's
//! `SmbClient.meaning(of:)` reads, so the three platforms name a refusal alike.

use std::fmt;

/// Why a share could not be reached or read. Each case is one the app words for the reader.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SmbError {
    /// Nothing answered at the address, the name did not resolve, or the server stopped
    /// answering. Grey in the library, never red (`AGENTS.md`, non-negotiable 3).
    HostUnreachable,
    /// The server answered and has no share of that name.
    ShareNotFound,
    /// The server refused the name and password.
    AuthenticationRejected,
    /// The server speaks only SMB 1. Refused by name, never fallen back to; the remedy names
    /// the server setting to change ([`SmbError::remedy`]).
    ProtocolUnsupported,
    /// The share demands encryption and this session could not give it.
    EncryptionRequired,
    /// The share was reached and the file or folder is not on it. Not a missing share: that
    /// sends a reader to their server settings for a typo in a file name.
    FileNotFound(String),
    /// Anything else, with what the library said, for a bug report.
    Unexpected(String),
}

impl SmbError {
    /// The server setting a reader changes, for the one failure a setting fixes.
    pub fn remedy(&self) -> Option<&'static str> {
        match self {
            Self::ProtocolUnsupported => Some(
                "Turn on SMB 2 or later on the server: on Samba, server min protocol = SMB2_02; \
                 on Windows, the SMB 2 and SMB 3 server; on a NAS, the minimum SMB protocol in \
                 its file services settings",
            ),
            _ => None,
        }
    }

    /// Whether this failure is the network rather than the server's answer, so the source
    /// shows grey and the reader keeps what is buffered.
    pub fn is_unreachable(&self) -> bool {
        matches!(self, Self::HostUnreachable)
    }
}

impl fmt::Display for SmbError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::HostUnreachable => f.write_str("the server cannot be reached"),
            Self::ShareNotFound => f.write_str("the server has no share of that name"),
            Self::AuthenticationRejected => f.write_str("the server refused the sign-in"),
            Self::ProtocolUnsupported => {
                f.write_str("the server speaks only SMB 1, which is disabled for security reasons")
            }
            Self::EncryptionRequired => f.write_str("the share requires encryption"),
            Self::FileNotFound(path) => write!(f, "nothing at {path} on the share"),
            Self::Unexpected(detail) => write!(f, "the share failed: {detail}"),
        }
    }
}

impl std::error::Error for SmbError {}

/// Where a failure happened, because a status means different things at each step.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Step {
    /// Negotiate, session setup, tree connect.
    Connect,
    /// Opening a file or a folder on a connected share.
    Open,
    /// A read on an open file.
    Read,
}

/// What a failed connect means before the SMB 1 probe and the encryption retry have run.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Failure {
    /// A failure with its final name.
    Named(SmbError),
    /// The two ends never agreed a dialect: the probe decides whether it was SMB 1.
    Handshake(String),
    /// Encryption was asked for and the server cannot give it: reconnect allowing none.
    EncryptionUnavailable,
}

/// `STATUS_LOGON_FAILURE`, `STATUS_WRONG_PASSWORD`, `STATUS_ACCESS_DENIED`.
const AUTH: [u32; 3] = [0xC000_006D, 0xC000_006A, 0xC000_0022];
/// `STATUS_BAD_NETWORK_NAME`.
const BAD_NETWORK_NAME: u32 = 0xC000_00CC;
/// `STATUS_OBJECT_NAME_NOT_FOUND`, `STATUS_OBJECT_PATH_NOT_FOUND`.
const NO_SUCH_PATH: [u32; 2] = [0xC000_0034, 0xC000_003A];
/// `STATUS_CONNECTION_DISCONNECTED`, `STATUS_CONNECTION_RESET`, `STATUS_NETWORK_NAME_DELETED`.
const DROPPED: [u32; 3] = [0xC000_020C, 0xC000_020D, 0xC000_00C9];
/// `STATUS_NETWORK_UNREACHABLE`, `STATUS_HOST_UNREACHABLE`, `STATUS_IO_TIMEOUT`.
const UNREACHABLE: [u32; 3] = [0xC000_023C, 0xC000_023D, 0xC000_00B5];

/// The meaning of an NT status at `step`, for `path` when a file is what was missing.
pub(crate) fn meaning_of_status(status: u32, step: Step, path: &str) -> SmbError {
    if AUTH.contains(&status) {
        return SmbError::AuthenticationRejected;
    }
    if status == BAD_NETWORK_NAME {
        return SmbError::ShareNotFound;
    }
    if NO_SUCH_PATH.contains(&status) {
        return match step {
            // A tree connect that finds no path is a share that is not there.
            Step::Connect => SmbError::ShareNotFound,
            Step::Open | Step::Read => SmbError::FileNotFound(path.to_owned()),
        };
    }
    if DROPPED.contains(&status) || UNREACHABLE.contains(&status) {
        return SmbError::HostUnreachable;
    }
    SmbError::Unexpected(format!("NT status {status:#010x}"))
}

/// What the crate's error means at `step`.
pub(crate) fn translate(error: &smb::Error, step: Step, path: &str) -> Failure {
    use smb::Error as E;
    match error {
        E::UnexpectedMessageStatus(status) | E::ReceivedErrorMessage(status, _) => {
            Failure::Named(meaning_of_status(*status, step, path))
        }
        E::OperationTimeout(..) | E::ConnectionStopped | E::Cancelled(_) => {
            Failure::Named(SmbError::HostUnreachable)
        }
        E::TransportError(transport) => transport_failure(transport, step),
        E::IoError(io) => io_failure(io, step),
        E::BinRWError(detail) if step == Step::Connect => Failure::Handshake(detail.to_string()),
        E::NegotiationError(detail) => Failure::Handshake(detail.clone()),
        E::InvalidMessage(detail)
            if detail.contains("Encryption is required by the connection") =>
        {
            Failure::EncryptionUnavailable
        }
        E::InvalidMessage(detail) if detail.contains("requires encryption") => {
            Failure::Named(SmbError::EncryptionRequired)
        }
        E::InvalidMessage(detail) if step == Step::Connect => Failure::Handshake(detail.clone()),
        other => Failure::Named(SmbError::Unexpected(other.to_string())),
    }
}

fn transport_failure(error: &smb::transport::TransportError, step: Step) -> Failure {
    use smb::transport::TransportError as T;
    match error {
        T::IoError(io) => io_failure(io, step),
        T::ParseError(detail) if step == Step::Connect => Failure::Handshake(detail.to_string()),
        T::InvalidMessage if step == Step::Connect => Failure::Handshake(error.to_string()),
        _ => Failure::Named(SmbError::HostUnreachable),
    }
}

fn io_failure(error: &std::io::Error, step: Step) -> Failure {
    use std::io::ErrorKind as K;
    match error.kind() {
        // A server that drops the connection the moment it reads an SMB 2 negotiate is what
        // an SMB 1 server with SMB 2 disabled looks like: let the probe ask.
        K::ConnectionReset | K::ConnectionAborted | K::UnexpectedEof if step == Step::Connect => {
            Failure::Handshake(error.to_string())
        }
        _ => Failure::Named(SmbError::HostUnreachable),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_four_named_failures_come_from_the_statuses_the_phones_read() {
        for status in AUTH {
            assert_eq!(
                meaning_of_status(status, Step::Connect, ""),
                SmbError::AuthenticationRejected
            );
        }
        assert_eq!(
            meaning_of_status(BAD_NETWORK_NAME, Step::Connect, ""),
            SmbError::ShareNotFound
        );
        assert_eq!(
            meaning_of_status(0xC000_023D, Step::Read, ""),
            SmbError::HostUnreachable
        );
    }

    #[test]
    fn a_missing_file_is_not_a_missing_share() {
        assert_eq!(
            meaning_of_status(0xC000_0034, Step::Open, "Sub/Gone.cbz"),
            SmbError::FileNotFound("Sub/Gone.cbz".into())
        );
        assert_eq!(
            meaning_of_status(0xC000_003A, Step::Connect, ""),
            SmbError::ShareNotFound
        );
    }

    #[test]
    fn an_unknown_status_is_unexpected_with_its_number() {
        assert_eq!(
            meaning_of_status(0xC000_0001, Step::Read, ""),
            SmbError::Unexpected("NT status 0xc0000001".into())
        );
    }

    #[test]
    fn a_reset_during_the_handshake_asks_the_probe_and_later_is_unreachable() {
        let reset = || std::io::Error::from(std::io::ErrorKind::ConnectionReset);
        assert!(matches!(
            translate(&smb::Error::IoError(reset()), Step::Connect, ""),
            Failure::Handshake(_)
        ));
        assert_eq!(
            translate(&smb::Error::IoError(reset()), Step::Read, ""),
            Failure::Named(SmbError::HostUnreachable)
        );
        let refused = std::io::Error::from(std::io::ErrorKind::ConnectionRefused);
        assert_eq!(
            translate(&smb::Error::IoError(refused), Step::Connect, ""),
            Failure::Named(SmbError::HostUnreachable)
        );
    }

    #[test]
    fn encryption_that_cannot_be_had_is_retried_and_one_demanded_is_named() {
        let asked = smb::Error::InvalidMessage(
            "Encryption is required by the connection config, but is not available!".into(),
        );
        assert_eq!(
            translate(&asked, Step::Connect, ""),
            Failure::EncryptionUnavailable
        );
        let demanded = smb::Error::InvalidMessage(
            "Server requires encryption, but client does not support it".into(),
        );
        assert_eq!(
            translate(&demanded, Step::Connect, ""),
            Failure::Named(SmbError::EncryptionRequired)
        );
    }

    #[test]
    fn only_protocol_unsupported_names_a_setting() {
        assert!(
            SmbError::ProtocolUnsupported
                .remedy()
                .unwrap()
                .contains("SMB 2")
        );
        assert!(SmbError::HostUnreachable.remedy().is_none());
        assert!(SmbError::HostUnreachable.is_unreachable());
    }
}
