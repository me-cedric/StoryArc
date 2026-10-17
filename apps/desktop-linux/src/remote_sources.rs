//! The network libraries the reader added (task 3.17): a share, a catalogue, a Kavita
//! server. Pure: what a record holds and what the sources file keeps of it (an id, a
//! name, an address and a user name, never a secret: `desktop-experience`, Saving a
//! password), what each form's entry means, the words for each named failure, and the
//! suggestions `avahi-browse` announces. `network_ui.rs` is the GTK side.

use storyarc_core::sources::kavita::{KavitaAddress, KavitaError};
use storyarc_core::sources::opds::{self, OpdsError, Received};
use storyarc_core::sources::smb::{SmbAddress, SmbError};

use crate::strings::{tr, tr_args};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Share,
    Catalogue,
    Kavita,
}

impl Kind {
    fn word(self) -> &'static str {
        match self {
            Self::Share => "share",
            Self::Catalogue => "catalogue",
            Self::Kavita => "kavita",
        }
    }

    fn of(word: &str) -> Option<Self> {
        match word {
            "share" => Some(Self::Share),
            "catalogue" => Some(Self::Catalogue),
            "kavita" => Some(Self::Kavita),
            _ => None,
        }
    }

    /// The word the library document uses for the kind.
    pub fn document_kind(self) -> &'static str {
        match self {
            Self::Share => "networkShare",
            Self::Catalogue => "opdsCatalog",
            Self::Kavita => "kavitaServer",
        }
    }

    /// The field a secret is filed under in the secure store.
    pub fn secret_field(self) -> &'static str {
        match self {
            Self::Share => "password",
            Self::Catalogue => "token",
            Self::Kavita => "apiKey",
        }
    }
}

/// One added network library. The secret is not here: `SecretKey::for_source(id, field)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RemoteRecord {
    pub id: String,
    pub kind: Kind,
    pub name: String,
    /// `smb://host:port/share/folder` or a web address, with no credential in it.
    pub address: String,
    pub username: Option<String>,
}

fn clean(text: &str) -> String {
    text.replace(['\t', '\n', '\r'], " ")
}

/// The remote sources file: one library a line, tab separated.
pub fn save(records: &[RemoteRecord]) -> String {
    records
        .iter()
        .map(|r| {
            format!(
                "{}\t{}\t{}\t{}\t{}\n",
                r.kind.word(),
                clean(&r.id),
                clean(&r.name),
                clean(&r.address),
                clean(r.username.as_deref().unwrap_or(""))
            )
        })
        .collect()
}

/// Reads the file back. A damaged line is skipped and an id listed twice is kept once.
pub fn restore(text: &str) -> Vec<RemoteRecord> {
    let mut records: Vec<RemoteRecord> = Vec::new();
    for line in text.lines() {
        let parts: Vec<&str> = line.split('\t').collect();
        let [kind, id, name, address, username] = parts[..] else {
            continue;
        };
        let Some(kind) = Kind::of(kind) else { continue };
        if id.is_empty() || address.is_empty() || records.iter().any(|r| r.id == id) {
            continue;
        }
        records.push(RemoteRecord {
            id: id.into(),
            kind,
            name: name.into(),
            address: address.into(),
            username: (!username.is_empty()).then(|| username.into()),
        });
    }
    records
}

/// What a share's address is, from the three fields of the sheet. A pasted
/// `smb://host/share` or `\\host\share` in the host field wins, as the hint says.
pub fn share_address(host: &str, share: &str, folder: &str) -> Option<SmbAddress> {
    let host = host.trim();
    if let Some(address) = SmbAddress::parse(host) {
        return Some(address);
    }
    if host.is_empty() || share.trim().is_empty() || host.contains(['/', '\\', ' ']) {
        return None;
    }
    let (name, port) = match host.rsplit_once(':') {
        Some((name, port)) if !name.contains(':') => (name, port.parse().ok()?),
        _ => (host, storyarc_core::sources::smb::DEFAULT_PORT),
    };
    Some(
        SmbAddress::new(name, share.trim())
            .with_port(port)
            .with_folder(folder),
    )
}

/// The address a share is saved under: no credential in it.
pub fn share_locator(address: &SmbAddress) -> String {
    let port = if address.port == storyarc_core::sources::smb::DEFAULT_PORT {
        String::new()
    } else {
        format!(":{}", address.port)
    };
    let folder = if address.folder.is_empty() {
        String::new()
    } else {
        format!("/{}", address.folder)
    };
    format!("smb://{}{port}/{}{folder}", address.host, address.share)
}

/// A saved locator back to an address.
pub fn share_of_locator(locator: &str) -> Option<SmbAddress> {
    SmbAddress::parse(locator)
}

pub fn catalogue_address(typed: &str) -> Option<String> {
    opds::address_from_typed(typed).map(|url| url.to_string())
}

pub fn kavita_address(typed: &str) -> Option<String> {
    KavitaAddress::parse(typed, "").map(|a| a.base.to_string())
}

/// A failure in the reader's words. Unreachable is grey; only a refusal the reader can
/// mend is asked about, and none is red.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Said {
    pub text: String,
    pub grey: bool,
    /// What to change, where one setting fixes it.
    pub remedy: Option<String>,
}

fn said(text: String, grey: bool) -> Said {
    Said {
        text,
        grey,
        remedy: None,
    }
}

pub fn smb_failure(error: &SmbError) -> Said {
    let (key, english, grey) = match error {
        SmbError::HostUnreachable => (
            "smb.error.hostUnreachable",
            "That host did not answer. Check the name and that the device is on the same network.",
            true,
        ),
        SmbError::ShareNotFound => (
            "smb.error.shareNotFound",
            "That share is not on this host.",
            true,
        ),
        SmbError::AuthenticationRejected => (
            "smb.error.authentication",
            "The user name or password was refused.",
            true,
        ),
        SmbError::ProtocolUnsupported => (
            "smb.error.smb1",
            "This server only offers SMB 1, which is disabled for security reasons. Enable SMB 2 or later on the server — on most NAS boxes that is under File Services, SMB.",
            true,
        ),
        SmbError::EncryptionRequired => (
            "smb.error.encryption",
            "This server requires SMB 3 encryption, and this connection could not be encrypted. A guest connection cannot be encrypted: sign in with a user name and password.",
            true,
        ),
        SmbError::FileNotFound(_) | SmbError::Unexpected(_) => (
            "smb.error.unexpected",
            "The share could not be reached.",
            true,
        ),
    };
    Said {
        remedy: error.remedy().map(str::to_owned),
        ..said(tr(key, english), grey)
    }
}

pub fn opds_failure(error: &OpdsError) -> Said {
    let text = match error {
        OpdsError::Empty => tr(
            "catalogue.error.empty",
            "The server answered with nothing at all.",
        ),
        OpdsError::NotAFeed(Received::Html) => tr(
            "catalogue.error.html",
            "That address returned a web page, not a catalogue. A sign-in page or a wrong path usually does this.",
        ),
        OpdsError::NotAFeed(Received::Unrecognised(kind)) => tr_args(
            "catalogue.error.notAFeed",
            "That address returned %s, which is not a catalogue.",
            &[&kind.clone().unwrap_or_else(|| {
                tr(
                    "catalogue.error.unknownType",
                    "something of an unknown type",
                )
            })],
        ),
        OpdsError::Malformed(_) => tr(
            "catalogue.error.malformed",
            "The catalogue could not be read.",
        ),
        OpdsError::Http(status) => tr_args(
            "catalogue.error.http",
            "The server refused: %1$d.",
            &[status],
        ),
        OpdsError::Unauthorized(_) => tr(
            "catalogue.error.unauthorized",
            "This catalogue refused the sign-in it was given.",
        ),
        OpdsError::Untrusted(certificate) => tr_args(
            "catalogue.untrusted.fingerprint %s",
            "Certificate fingerprint: %s",
            &[&certificate.fingerprint],
        ),
        OpdsError::Downgrade | OpdsError::RefusedAddress => tr(
            "catalogue.error.refusedAddress",
            "This catalogue pointed somewhere StoryArc will not follow — an address that is not a web address, or a plain-HTTP one from a server you reach securely.",
        ),
        OpdsError::Redirect => tr(
            "catalogue.error.redirect",
            "This catalogue's address redirects in a loop, or redirected with no address to follow.",
        ),
        OpdsError::Unreachable(_) => tr(
            "catalogue.error.unreachable",
            "This server could not be reached.",
        ),
    };
    said(text, true)
}

pub fn kavita_failure(error: &KavitaError) -> Said {
    let text = match error {
        KavitaError::BadAddress => tr(
            "kavita.error.notAnAddress",
            "That is not an address StoryArc can reach.",
        ),
        KavitaError::KeyRejected => tr(
            "kavita.error.keyRejected",
            "That API key was refused. Check it in your Kavita account settings.",
        ),
        KavitaError::RouteMissing(_) => tr(
            "kavita.error.tooOldForRequest",
            "That server is too old for StoryArc. It does not know the request StoryArc sends.",
        ),
        KavitaError::UnexpectedResponse | KavitaError::Http(_) => tr(
            "kavita.error.notKavita",
            "That address answered, but not like a Kavita server.",
        ),
        KavitaError::Unreachable(_) => tr(
            "catalogue.error.unreachable",
            "This server could not be reached.",
        ),
    };
    said(text, true)
}

/// A share the system announced on the local network.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Suggestion {
    pub name: String,
    pub host: String,
    pub port: u16,
}

/// Reads `avahi-browse -tpr _smb._tcp` (parseable, resolved): lines that begin with `=`
/// carry `iface;protocol;name;type;domain;host;address;port;txt`. Each host once, in the
/// order announced. Anything else is ignored.
pub fn parse_avahi(output: &str) -> Vec<Suggestion> {
    let mut found: Vec<Suggestion> = Vec::new();
    for line in output.lines() {
        let Some(rest) = line.strip_prefix('=') else {
            continue;
        };
        let parts: Vec<&str> = rest.split(';').collect();
        if parts.len() < 9 {
            continue;
        }
        let (name, host, port) = (parts[3], parts[6], parts[8]);
        let Ok(port) = port.parse::<u16>() else {
            continue;
        };
        let name = name.replace("\\032", " ");
        if host.is_empty() || found.iter().any(|s| s.host == host) {
            continue;
        }
        found.push(Suggestion {
            name,
            host: host.to_owned(),
            port,
        });
    }
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(kind: Kind, id: &str) -> RemoteRecord {
        RemoteRecord {
            id: id.into(),
            kind,
            name: "NAS".into(),
            address: "smb://nas/comics".into(),
            username: Some("ada".into()),
        }
    }

    #[test]
    fn the_file_keeps_an_id_a_name_an_address_and_a_user_and_no_secret() {
        let records = vec![record(Kind::Share, "a"), record(Kind::Kavita, "b")];
        let text = save(&records);
        assert_eq!(restore(&text), records);
        assert!(!text.contains("lovelace"));
    }

    #[test]
    fn a_damaged_or_repeated_line_is_skipped() {
        let text = "share\ta\tNAS\tsmb://nas/c\t\nnonsense\nshare\ta\tAgain\tsmb://x/y\t\nfoo\tb\tn\ta\t\n";
        let records = restore(text);
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].name, "NAS");
        assert_eq!(records[0].username, None);
    }

    #[test]
    fn a_tab_in_a_name_cannot_split_a_line() {
        let mut r = record(Kind::Catalogue, "c");
        r.name = "My\tlibrary".into();
        assert_eq!(restore(&save(&[r]))[0].name, "My library");
    }

    #[test]
    fn a_pasted_address_fills_the_form_and_its_credentials_are_dropped() {
        let a = share_address("smb://ada:pw@nas:4445/comics/new", "", "").unwrap();
        assert_eq!(
            (a.host.as_str(), a.port, a.share.as_str()),
            ("nas", 4445, "comics")
        );
        assert_eq!(a.folder, "new");
        assert!(!share_locator(&a).contains("pw"));
    }

    #[test]
    fn a_host_with_a_port_and_a_share_makes_an_address_and_no_host_is_refused() {
        let a = share_address("nas.local:4445", "comics", "/sub/").unwrap();
        assert_eq!(share_locator(&a), "smb://nas.local:4445/comics/sub");
        assert_eq!(share_of_locator(&share_locator(&a)), Some(a));
        assert!(share_address("", "comics", "").is_none());
        assert!(share_address("nas", "", "").is_none());
        assert!(share_address("na s", "c", "").is_none());
    }

    #[test]
    fn a_catalogue_and_a_server_assume_https_and_refuse_a_sentence() {
        assert_eq!(
            catalogue_address("opds.example.org/feed").as_deref(),
            Some("https://opds.example.org/feed")
        );
        assert!(catalogue_address("not an address").is_none());
        assert!(kavita_address("ftp://x").is_none());
        assert!(kavita_address("kavita.local:5000").is_some());
    }

    #[test]
    fn every_named_share_failure_is_grey_and_the_old_protocol_names_a_setting() {
        for error in [
            SmbError::HostUnreachable,
            SmbError::ShareNotFound,
            SmbError::AuthenticationRejected,
            SmbError::ProtocolUnsupported,
            SmbError::EncryptionRequired,
        ] {
            assert!(smb_failure(&error).grey);
        }
        assert!(smb_failure(&SmbError::ProtocolUnsupported).remedy.is_some());
        assert!(smb_failure(&SmbError::HostUnreachable).remedy.is_none());
        assert_ne!(
            smb_failure(&SmbError::ShareNotFound).text,
            smb_failure(&SmbError::AuthenticationRejected).text
        );
    }

    #[test]
    fn a_refused_key_and_an_unreachable_server_read_differently() {
        assert_ne!(
            kavita_failure(&KavitaError::KeyRejected).text,
            kavita_failure(&KavitaError::Unreachable("x".into())).text
        );
        assert_ne!(
            opds_failure(&OpdsError::Http(404)).text,
            opds_failure(&OpdsError::Empty).text
        );
    }

    #[test]
    fn avahi_lines_become_suggestions_once_per_host() {
        let output = "+;eth0;IPv4;NAS;_smb._tcp;local\n\
=;eth0;IPv4;My\\032NAS;_smb._tcp;local;nas.local;192.168.1.5;445;\"\"\n\
=;eth0;IPv6;My\\032NAS;_smb._tcp;local;nas.local;fe80::1;445;\"\"\n\
=;eth0;IPv4;Other;_smb._tcp;local;other.local;192.168.1.6;4445;\"\"\n\
=;eth0;IPv4;Broken;_smb._tcp;local;x.local;1.1.1.1;port;\"\"\n";
        let found = parse_avahi(output);
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].name, "My NAS");
        assert_eq!(found[1].port, 4445);
        assert!(parse_avahi("").is_empty());
    }
}
