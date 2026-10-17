//! SMB shares (task 3.2 of `desktop-clients`; `network-share`; `desktop-experience`, *Finding
//! and reaching a network share*).
//!
//! An in-app client rather than the system's redirector (design.md, Decision 7), through the
//! `smb` crate, which won the spike in `docs/delivery/desktop-spike-smb.md` because it reads a
//! share that requires encryption. Everything above this module works against
//! [`RandomAccessSource`](crate::io::RandomAccessSource) and learns nothing about SMB: an
//! [`SmbFile`] is the third implementation ADR-0008 planned for.
//!
//! What it owns, each with its rule:
//!
//! - **The four named failures** of *Adding a share*, plus the SMB 1 refusal with its remedy
//!   ([`SmbError`]); an SMB 1 server is recognised by the probe of [`probe`].
//! - **Encryption.** A connection asks for encryption first, and a session that connected with
//!   encryption required is encrypted; a server that cannot give it is reconnected allowing
//!   none and reported as not encrypted ([`SmbIdentity::is_encrypted`]).
//! - **The two-second and sixty-second rules** ([`ReadHealth`]).
//! - **Sleep, a dropped connection, a changed network.** A read that fails drops the session,
//!   opens a new one and asks once more, so a laptop that slept reads on without a prompt; the
//!   app may also drop the session itself on a wake or a network change
//!   ([`SmbFile::drop_session`]).

mod error;
mod file;
mod health;
pub mod probe;
mod share;

pub use error::SmbError;
pub use file::SmbFile;
pub use health::{BLOCKED_INDICATOR_AFTER, OFFER_OFFLINE_AFTER, ReadHealth, ReadStatus};
pub use share::{SmbEntry, SmbShare};

use crate::secrets::Secret;

/// The port SMB listens on when an address names none.
pub const DEFAULT_PORT: u16 = 445;

/// Where a share is: a host, a port, the share's name and the folder inside it used as the
/// library's root.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SmbAddress {
    pub host: String,
    pub port: u16,
    pub share: String,
    /// A folder inside the share, `/`-separated, empty for the share's root.
    pub folder: String,
}

impl SmbAddress {
    pub fn new(host: impl Into<String>, share: impl Into<String>) -> Self {
        Self {
            host: host.into(),
            port: DEFAULT_PORT,
            share: share.into(),
            folder: String::new(),
        }
    }

    pub fn with_port(self, port: u16) -> Self {
        Self { port, ..self }
    }

    pub fn with_folder(self, folder: impl Into<String>) -> Self {
        Self {
            folder: folder.into().trim_matches('/').to_owned(),
            ..self
        }
    }

    /// Reads what a reader pastes: `smb://host[:port]/share[/folder]` or `\\host\share[\folder]`.
    /// `None` when there is no host or no share in it.
    pub fn parse(pasted: &str) -> Option<Self> {
        let text = pasted.trim();
        let rest = if let Some(rest) = text.strip_prefix("smb://") {
            rest.to_owned()
        } else {
            text.strip_prefix(r"\\")?.replace('\\', "/")
        };
        let mut parts = rest.split('/').filter(|part| !part.is_empty());
        let authority = parts.next()?;
        let share = parts.next()?;
        let folder = parts.collect::<Vec<_>>().join("/");
        // Credentials in a pasted address are dropped: they belong in the secure store.
        let authority = authority.rsplit('@').next().unwrap_or(authority);
        let (host, port) = match authority.rsplit_once(':') {
            Some((host, port)) if !host.contains(':') || host.starts_with('[') => {
                (host, port.parse().ok()?)
            }
            _ => (authority, DEFAULT_PORT),
        };
        if host.is_empty() {
            return None;
        }
        Some(Self::new(host, share).with_port(port).with_folder(folder))
    }

    /// How a source names the share in a list: `host/share`.
    pub fn display_name(&self) -> String {
        format!("{}/{}", self.host, self.share)
    }

    /// `folder` and `path` joined, the path on the share a call asks for.
    pub(crate) fn inside(&self, path: &str) -> String {
        let path = path.trim_matches('/');
        match (self.folder.is_empty(), path.is_empty()) {
            (true, _) => path.to_owned(),
            (false, true) => self.folder.clone(),
            (false, false) => format!("{}/{path}", self.folder),
        }
    }
}

/// Who signs in. A password is a [`Secret`], so it never prints.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SmbLogin {
    Guest,
    Account { username: String, password: Secret },
}

impl SmbLogin {
    pub fn account(username: impl Into<String>, password: impl Into<Secret>) -> Self {
        Self::Account {
            username: username.into(),
            password: password.into(),
        }
    }

    pub fn is_guest(&self) -> bool {
        matches!(self, Self::Guest)
    }
}

/// What a connection turned out to be, for the source's detail and the add sheet.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SmbIdentity {
    /// The negotiated dialect as the reader sees it: "SMB 3.1.1".
    pub dialect: String,
    /// Every message after the session setup is sealed.
    pub is_encrypted: bool,
}

/// How a dialect revision is written, as StoryArcKit's `SmbClient.name(of:)` writes it.
pub(crate) fn dialect_name(dialect: smb::Dialect) -> &'static str {
    match dialect {
        smb::Dialect::Smb0202 => "SMB 2.0.2",
        smb::Dialect::Smb021 => "SMB 2.1",
        smb::Dialect::Smb030 => "SMB 3.0",
        smb::Dialect::Smb0302 => "SMB 3.0.2",
        smb::Dialect::Smb0311 => "SMB 3.1.1",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pasted_url_and_a_unc_path_read_the_same() {
        let url = SmbAddress::parse("smb://nas.local:4445/Comics/Marvel/1990s").unwrap();
        let unc = SmbAddress::parse(r"\\nas.local\Comics\Marvel\1990s").unwrap();
        assert_eq!(url.host, "nas.local");
        assert_eq!(url.port, 4445);
        assert_eq!(url.share, "Comics");
        assert_eq!(url.folder, "Marvel/1990s");
        assert_eq!(unc.port, DEFAULT_PORT);
        assert_eq!(unc.folder, url.folder);
    }

    #[test]
    fn credentials_in_a_pasted_address_are_dropped() {
        let address = SmbAddress::parse("smb://ada:lovelace@nas/Comics").unwrap();
        assert_eq!(address.host, "nas");
        assert!(!format!("{address:?}").contains("lovelace"));
    }

    #[test]
    fn an_address_with_no_share_is_refused() {
        assert!(SmbAddress::parse("smb://nas").is_none());
        assert!(SmbAddress::parse("nas/Comics").is_none());
        assert!(SmbAddress::parse("smb://:445/Comics").is_none());
    }

    #[test]
    fn a_path_is_joined_under_the_chosen_folder() {
        let address = SmbAddress::new("nas", "Comics").with_folder("/Marvel/");
        assert_eq!(address.inside("Spider/1.cbz"), "Marvel/Spider/1.cbz");
        assert_eq!(address.inside(""), "Marvel");
        assert_eq!(SmbAddress::new("nas", "Comics").inside("/a.cbz"), "a.cbz");
    }

    #[test]
    fn a_password_never_prints() {
        let login = SmbLogin::account("ada", "lovelace");
        assert!(!format!("{login:?}").contains("lovelace"));
        assert!(!login.is_guest());
    }

    #[test]
    fn dialects_are_named_as_the_phones_name_them() {
        assert_eq!(dialect_name(smb::Dialect::Smb0311), "SMB 3.1.1");
        assert_eq!(dialect_name(smb::Dialect::Smb021), "SMB 2.1");
    }
}
