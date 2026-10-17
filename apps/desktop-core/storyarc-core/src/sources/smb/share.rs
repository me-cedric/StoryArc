//! A connected share: validate, list, open.

use std::str::FromStr;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_util::StreamExt;
use smb::connection::EncryptionMode;
use smb::{
    Client, ClientConfig, ConnectionConfig, DirAccessMask, Directory, FileAccessMask,
    FileCreateArgs, FileDirectoryInformation, GetLen, UncPath,
};

use super::error::{Failure, SmbError, Step, translate};
use super::file::{OpenFile, SmbFile};
use super::probe;
use super::{SmbAddress, SmbIdentity, SmbLogin, dialect_name};
use crate::domain::NaturalOrder;
use crate::runtime::{InRuntime, Runtime};

/// How long a connect, or a reply on a connected session, may take before the server counts as
/// unreachable. Android's `SmbClient.kt` and iOS's `SmbSource` bound a reply at 20 s and a
/// reopen at 10 s; the crate's own timeout is per reply, so it takes the shorter.
pub(crate) const REPLY_TIMEOUT: Duration = Duration::from_secs(10);
/// The SMB 1 probe's own bound.
const PROBE_TIMEOUT: Duration = Duration::from_secs(3);

/// One entry of a folder on a share.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SmbEntry {
    pub name: String,
    /// The path from the address's folder, `/`-separated.
    pub path: String,
    pub is_directory: bool,
    pub length: u64,
}

/// What a reopen needs: where, who, and the encryption the first connect settled on.
#[derive(Debug, Clone)]
pub(crate) struct Target {
    pub address: SmbAddress,
    pub login: SmbLogin,
    pub encryption: EncryptionMode,
}

impl Target {
    fn unc(&self) -> Result<UncPath, SmbError> {
        UncPath::from_str(&format!(r"\\{}\{}", self.address.host, self.address.share))
            .map_err(|error| SmbError::Unexpected(error.to_string()))
    }

    /// A fresh client signed in to the share.
    pub(crate) async fn connect(&self) -> Result<(Client, UncPath), Failure> {
        let unc = self.unc().map_err(Failure::Named)?;
        let client = Client::new(ClientConfig {
            dfs: false,
            connection: ConnectionConfig {
                port: Some(self.address.port),
                timeout: Some(REPLY_TIMEOUT),
                encryption_mode: self.encryption,
                allow_unsigned_guest_access: self.login.is_guest(),
                ..ConnectionConfig::default()
            },
            ..ClientConfig::default()
        });
        let (user, password) = match &self.login {
            SmbLogin::Guest => ("Guest".to_owned(), String::new()),
            SmbLogin::Account { username, password } => {
                (username.clone(), password.expose().to_owned())
            }
        };
        client
            .share_connect(&unc, &user, password)
            .await
            .map_err(|error| translate(&error, Step::Connect, ""))?;
        Ok((client, unc))
    }

    /// Opens `path` (already joined under the folder) for reading on a fresh client.
    pub(crate) async fn open_file(&self, path: &str) -> Result<OpenFile, SmbError> {
        let (client, unc) = self.connect().await.map_err(|failure| match failure {
            Failure::Named(error) => error,
            Failure::Handshake(_) | Failure::EncryptionUnavailable => SmbError::HostUnreachable,
        })?;
        let resource = client
            .create_file(
                &unc.with_path(path),
                &FileCreateArgs::make_open_existing(FileAccessMask::new().with_generic_read(true)),
            )
            .await
            .map_err(|error| named(&error, Step::Open, path))?;
        let file = resource
            .as_file()
            .is_some()
            .then(|| resource.unwrap_file())
            .ok_or_else(|| SmbError::FileNotFound(path.to_owned()))?;
        let length = file
            .get_len()
            .await
            .map_err(|error| named(&error, Step::Open, path))?;
        Ok(OpenFile::new(client, file, length))
    }
}

/// A failure that is final at a step past the handshake.
pub(crate) fn named(error: &smb::Error, step: Step, path: &str) -> SmbError {
    match translate(error, step, path) {
        Failure::Named(error) => error,
        Failure::Handshake(detail) => SmbError::Unexpected(detail),
        Failure::EncryptionUnavailable => SmbError::EncryptionRequired,
    }
}

/// A share the reader added, signed in and validated.
pub struct SmbShare {
    runtime: Runtime,
    target: Target,
    identity: SmbIdentity,
    /// The session listings use. Files get their own, so a slow listing never holds a page.
    session: Mutex<Option<InRuntime<(Client, UncPath)>>>,
}

impl SmbShare {
    /// Connects and validates, as *Adding a share* asks: host, share and credentials are all
    /// exercised, and a failure is one of the named [`SmbError`] cases.
    pub fn connect(
        runtime: &Runtime,
        address: SmbAddress,
        login: SmbLogin,
    ) -> Result<Self, SmbError> {
        let (target, client, unc, identity) = runtime.block_on(establish(address, login))?;
        Ok(Self {
            runtime: runtime.clone(),
            target,
            identity,
            session: Mutex::new(Some(InRuntime::new(runtime, (client, unc)))),
        })
    }

    /// Validates and lets go: what the add sheet calls before it saves a source.
    pub fn check(
        runtime: &Runtime,
        address: SmbAddress,
        login: SmbLogin,
    ) -> Result<SmbIdentity, SmbError> {
        Self::connect(runtime, address, login).map(|share| share.identity)
    }

    /// What this connection negotiated.
    pub fn identity(&self) -> &SmbIdentity {
        &self.identity
    }

    pub fn address(&self) -> &SmbAddress {
        &self.target.address
    }

    /// One folder of the share, under the address's folder: folders first, then natural order.
    pub fn list(&self, path: &str) -> Result<Vec<SmbEntry>, SmbError> {
        let inside = self.target.address.inside(path);
        let mut slot = self
            .session
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let result = self.runtime.block_on(async {
            if slot.is_none() {
                let connected = self
                    .target
                    .connect()
                    .await
                    .map_err(|failure| match failure {
                        Failure::Named(error) => error,
                        _ => SmbError::HostUnreachable,
                    })?;
                *slot = Some(InRuntime::new(&self.runtime, connected));
            }
            let (client, unc) = &**slot.as_ref().expect("connected just above");
            list(client, unc, &inside).await
        });
        if result.as_ref().is_err_and(SmbError::is_unreachable) {
            *slot = None;
        }
        let relative = path.trim_matches('/');
        result.map(|entries| {
            entries
                .into_iter()
                .map(|(name, is_directory, length)| SmbEntry {
                    path: if relative.is_empty() {
                        name.clone()
                    } else {
                        format!("{relative}/{name}")
                    },
                    name,
                    is_directory,
                    length,
                })
                .collect()
        })
    }

    /// One file of the share, read where the reader needs it.
    pub fn open(&self, path: &str) -> Result<SmbFile, SmbError> {
        let inside = self.target.address.inside(path);
        let file = self.runtime.block_on(self.target.open_file(&inside))?;
        Ok(SmbFile::new(
            self.runtime.clone(),
            Arc::new(self.target.clone()),
            inside,
            file,
        ))
    }
}

impl std::fmt::Debug for SmbShare {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SmbShare")
            .field("address", &self.target.address)
            .field("identity", &self.identity)
            .finish()
    }
}

/// The first connect: encryption asked for, then allowed if the server cannot give it, then
/// the SMB 1 probe if no dialect was agreed at all.
async fn establish(
    address: SmbAddress,
    login: SmbLogin,
) -> Result<(Target, Client, UncPath, SmbIdentity), SmbError> {
    let mut target = Target {
        address,
        login,
        encryption: EncryptionMode::Required,
    };
    let attempt = match target.connect().await {
        Err(Failure::EncryptionUnavailable) => {
            target.encryption = EncryptionMode::Allowed;
            target.connect().await
        }
        other => other,
    };
    let (client, unc) = match attempt {
        Ok(connected) => connected,
        Err(Failure::Named(error)) => return Err(error),
        Err(Failure::EncryptionUnavailable) => return Err(SmbError::EncryptionRequired),
        Err(Failure::Handshake(detail)) => {
            let host = target.address.host.clone();
            let port = target.address.port;
            let is_smb1 = tokio::task::spawn_blocking(move || {
                probe::is_smb1_only(&host, port, PROBE_TIMEOUT)
            })
            .await
            .unwrap_or(false);
            return Err(if is_smb1 {
                SmbError::ProtocolUnsupported
            } else {
                SmbError::Unexpected(detail)
            });
        }
    };
    let dialect = client
        .get_connection(&target.address.host)
        .await
        .ok()
        .and_then(|connection| {
            connection
                .conn_info()
                .map(|info| info.negotiation.dialect_rev)
        })
        .map(dialect_name)
        .unwrap_or("SMB 2")
        .to_owned();
    let identity = SmbIdentity {
        dialect,
        is_encrypted: target.encryption == EncryptionMode::Required,
    };
    Ok((target, client, unc, identity))
}

/// Names, kinds and lengths of one folder, folders first, natural order within each.
async fn list(
    client: &Client,
    unc: &UncPath,
    path: &str,
) -> Result<Vec<(String, bool, u64)>, SmbError> {
    let at = if path.is_empty() {
        unc.clone()
    } else {
        unc.clone().with_path(path)
    };
    let resource = client
        .create_file(
            &at,
            &FileCreateArgs::make_open_existing(
                DirAccessMask::new().with_list_directory(true).into(),
            ),
        )
        .await
        .map_err(|error| named(&error, Step::Open, path))?;
    if !resource.is_dir() {
        return Err(SmbError::FileNotFound(path.to_owned()));
    }
    let directory = Arc::new(resource.unwrap_dir());
    let mut entries = Vec::new();
    {
        let mut stream = Directory::query::<FileDirectoryInformation>(&directory, "*")
            .await
            .map_err(|error| named(&error, Step::Read, path))?;
        while let Some(entry) = stream.next().await {
            let entry = entry.map_err(|error| named(&error, Step::Read, path))?;
            let name = entry.file_name.to_string();
            if name == "." || name == ".." {
                continue;
            }
            let is_directory = entry.file_attributes.directory();
            let length = if is_directory { 0 } else { entry.end_of_file };
            entries.push((name, is_directory, length));
        }
    }
    let _ = directory.close().await;
    entries.sort_by(|left, right| {
        right
            .1
            .cmp(&left.1)
            .then_with(|| NaturalOrder::compare(&left.0, &right.0))
    });
    Ok(entries)
}
