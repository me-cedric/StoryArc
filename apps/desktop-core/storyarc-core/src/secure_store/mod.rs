//! The system's secure store behind one trait (task 3.3 of `desktop-clients`; design.md,
//! Decision 7; `desktop-experience`, *Secrets in the system's own store*).
//!
//! | System | Backend | Where |
//! | --- | --- | --- |
//! | Windows | Credential Manager, `CRED_PERSIST_LOCAL_MACHINE`, each blob at most 2560 bytes | [`windows`] |
//! | Linux | Secret Service on the host, the portal's encrypted file keyring in a Flatpak (`oo7`) | [`linux`] |
//! | Neither running | Nothing written; the secret lives for the session and the app says so once | [`UnavailableStore`] |
//! | macOS | The keychain, through StoryArcKit; this core is not used there | none |
//!
//! The apps call [`Vault`], never a backend: it is what turns "no store" into a session-only
//! secret and a single grey notice, and "the store refused" into a failure with no copy kept.
//! A source's record holds only its id; [`SecretKey::for_source`] derives the reference.

mod memory;

#[cfg(target_os = "linux")]
pub mod linux;
#[cfg(windows)]
pub mod windows;

use std::collections::HashMap;
use std::fmt;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

pub use memory::{MemorySecretStore, UnavailableStore};

use crate::secrets::Secret;

/// The service every StoryArc secret is filed under.
pub const SERVICE: &str = "com.mecedric.StoryArc";

/// The largest secret Windows' Credential Manager keeps: `CRED_MAX_CREDENTIAL_BLOB_SIZE`,
/// five times 512 bytes.
pub const WINDOWS_BLOB_LIMIT: usize = 2560;

/// What a reader is told when no store runs, naming what supplies one.
#[cfg(not(windows))]
pub const UNAVAILABLE_REMEDY: &str = "No Secret Service is running, so passwords are kept until \
     StoryArc quits. Start GNOME Keyring, KWallet, KeePassXC or oo7-daemon to keep them.";
#[cfg(windows)]
pub const UNAVAILABLE_REMEDY: &str = "Credential Manager is not available, so passwords are kept \
     until StoryArc quits.";

/// Which secret: one field of one source.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SecretKey {
    account: String,
}

impl SecretKey {
    /// The key of `field` ("password", "token", "apiKey") of the source with `source_id`.
    pub fn for_source(source_id: &str, field: &str) -> Self {
        Self {
            account: format!("source/{source_id}/{field}"),
        }
    }

    /// The account name the store files it under, beside [`SERVICE`].
    pub fn account(&self) -> &str {
        &self.account
    }
}

/// Why a store could not do what it was asked. No case carries the secret.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SecretStoreError {
    /// No store is running. [`Vault`] turns this into a session-only secret.
    Unavailable,
    /// The reader denied the store's prompt, or the store is locked and stayed locked.
    Denied,
    /// The store refused, with its own words, which never hold the secret.
    Refused(String),
    /// The secret is larger than the store keeps.
    TooLarge { limit: usize },
}

impl fmt::Display for SecretStoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unavailable => f.write_str("no secure store is available"),
            Self::Denied => f.write_str("the secure store was not unlocked"),
            Self::Refused(reason) => write!(f, "the secure store refused: {reason}"),
            Self::TooLarge { limit } => {
                write!(
                    f,
                    "the secret is longer than the {limit} bytes the store keeps"
                )
            }
        }
    }
}

impl std::error::Error for SecretStoreError {}

/// Whether a store can be written now.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Availability {
    Available,
    Unavailable,
}

/// A secure store. Implementations never log, print or persist a secret anywhere else.
pub trait SecretStore: Send + Sync {
    fn availability(&self) -> Availability;
    fn save(&self, key: &SecretKey, secret: &Secret) -> Result<(), SecretStoreError>;
    /// `Ok(None)` when nothing is stored under `key`.
    fn load(&self, key: &SecretKey) -> Result<Option<Secret>, SecretStoreError>;
    /// Removing what is not there succeeds.
    fn delete(&self, key: &SecretKey) -> Result<(), SecretStoreError>;
}

/// What became of a saved secret.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SaveOutcome {
    /// In the system's store.
    Stored,
    /// Held in memory until the app quits. `notice` is present the first time only: the app
    /// says it once, in grey.
    SessionOnly { notice: Option<Notice> },
}

/// The one grey line an app shows when no store runs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notice {
    pub remedy: &'static str,
}

/// The app's door to secrets: the system store, or the session when there is none.
pub struct Vault {
    store: Box<dyn SecretStore>,
    session: Mutex<HashMap<SecretKey, Secret>>,
    noticed: AtomicBool,
}

impl Vault {
    pub fn new(store: Box<dyn SecretStore>) -> Self {
        Self {
            store,
            session: Mutex::new(HashMap::new()),
            noticed: AtomicBool::new(false),
        }
    }

    /// Whether secrets outlive this launch.
    pub fn is_session_only(&self) -> bool {
        self.store.availability() == Availability::Unavailable
    }

    /// Saves to the store, or for the session when there is none. A refusal keeps no copy, so
    /// the source shows as needing a sign-in.
    pub fn save(&self, key: &SecretKey, secret: Secret) -> Result<SaveOutcome, SecretStoreError> {
        if self.store.availability() == Availability::Available {
            match self.store.save(key, &secret) {
                Ok(()) => {
                    self.session().remove(key);
                    return Ok(SaveOutcome::Stored);
                }
                Err(SecretStoreError::Unavailable) => {}
                Err(error) => {
                    self.session().remove(key);
                    return Err(error);
                }
            }
        }
        self.session().insert(key.clone(), secret);
        let first = !self.noticed.swap(true, Ordering::SeqCst);
        Ok(SaveOutcome::SessionOnly {
            notice: first.then_some(Notice {
                remedy: UNAVAILABLE_REMEDY,
            }),
        })
    }

    /// The secret under `key`, from the session first, then from the store.
    pub fn load(&self, key: &SecretKey) -> Result<Option<Secret>, SecretStoreError> {
        if let Some(secret) = self.session().get(key) {
            return Ok(Some(secret.clone()));
        }
        match self.store.availability() {
            Availability::Available => self.store.load(key),
            Availability::Unavailable => Ok(None),
        }
    }

    /// Forgets the secret everywhere: what a removed source asks.
    pub fn delete(&self, key: &SecretKey) -> Result<(), SecretStoreError> {
        self.session().remove(key);
        match self.store.availability() {
            Availability::Available => self.store.delete(key),
            Availability::Unavailable => Ok(()),
        }
    }

    fn session(&self) -> std::sync::MutexGuard<'_, HashMap<SecretKey, Secret>> {
        self.session
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

impl fmt::Debug for Vault {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Vault")
            .field("session_only", &self.is_session_only())
            .finish()
    }
}

/// The store this system offers, or [`UnavailableStore`] when none answers.
///
/// Linux asks Secret Service (or the portal's file keyring in a Flatpak) through `oo7` on the
/// core's runtime; Windows opens Credential Manager. Other systems have no backend here.
pub fn system_store(runtime: &crate::runtime::Runtime) -> Box<dyn SecretStore> {
    #[cfg(target_os = "linux")]
    {
        match linux::SecretServiceStore::connect(runtime) {
            Ok(store) => Box::new(store),
            Err(_) => Box::new(UnavailableStore::new()),
        }
    }
    #[cfg(windows)]
    {
        let _ = runtime;
        match windows::CredentialManagerStore::open() {
            Ok(store) => Box::new(store),
            Err(_) => Box::new(UnavailableStore::new()),
        }
    }
    #[cfg(not(any(target_os = "linux", windows)))]
    {
        let _ = runtime;
        Box::new(UnavailableStore::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_key_names_the_source_and_the_field() {
        let key = SecretKey::for_source("abc", "token");
        assert_eq!(key.account(), "source/abc/token");
    }

    #[test]
    fn a_save_after_a_session_only_save_moves_the_secret_to_the_store() {
        let vault = Vault::new(Box::new(MemorySecretStore::new()));
        let key = SecretKey::for_source("s", "password");
        vault.session().insert(key.clone(), Secret::new("old"));
        assert_eq!(
            vault.save(&key, Secret::new("new")).unwrap(),
            SaveOutcome::Stored
        );
        assert!(vault.session().is_empty());
        assert_eq!(vault.load(&key).unwrap().unwrap().expose(), "new");
    }

    #[test]
    fn this_host_without_a_backend_is_session_only() {
        let runtime = crate::runtime::Runtime::new().unwrap();
        let store = system_store(&runtime);
        if cfg!(not(any(target_os = "linux", windows))) {
            assert_eq!(store.availability(), Availability::Unavailable);
        }
    }
}
