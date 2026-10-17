//! Windows: Credential Manager through `keyring-core` and `windows-native-keyring-store`
//! (design.md, Decision 7).
//!
//! - **Persistence is set explicitly** to `Local` (`CRED_PERSIST_LOCAL_MACHINE`): the crate's
//!   default is `Enterprise`, which roams a secret to other machines through the reader's
//!   domain profile, and `desktop-experience` keeps nothing in a roaming place.
//! - **Each blob is at most 2560 bytes** (`CRED_MAX_CREDENTIAL_BLOB_SIZE`), checked before the
//!   store is asked, so the failure is named rather than a platform error code.
//! - **One operation at a time.** The crate's own README warns that operations on one entry
//!   from two threads do not keep their order; a mutex keeps them in the order they were asked.
//! - **No error carries the secret.** `keyring_core::Error::BadEncoding` holds the stored
//!   bytes; it is translated without them, and nothing here formats a crate error with `{:?}`.
//!
//! Compiled only on Windows, and run there by the `desktop-windows` workflow; this module is
//! not built on the Mac or Linux hosts.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use keyring_core::api::CredentialStoreApi;

use super::{Availability, SERVICE, SecretKey, SecretStore, SecretStoreError, WINDOWS_BLOB_LIMIT};
use crate::secrets::Secret;

/// Credential Manager, as the current user sees it.
pub struct CredentialManagerStore {
    store: Arc<windows_native_keyring_store::Store>,
    order: Mutex<()>,
}

impl CredentialManagerStore {
    pub fn open() -> Result<Self, SecretStoreError> {
        let store =
            windows_native_keyring_store::Store::new().map_err(|error| translate(&error))?;
        Ok(Self {
            store,
            order: Mutex::new(()),
        })
    }

    fn entry(&self, key: &SecretKey) -> Result<keyring_core::Entry, SecretStoreError> {
        let modifiers = HashMap::from([("persistence", "Local")]);
        self.store
            .build(SERVICE, key.account(), Some(&modifiers))
            .map_err(|error| translate(&error))
    }

    fn in_order<T>(&self, body: impl FnOnce() -> T) -> T {
        let _turn = self
            .order
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        body()
    }
}

impl SecretStore for CredentialManagerStore {
    fn availability(&self) -> Availability {
        Availability::Available
    }

    fn save(&self, key: &SecretKey, secret: &Secret) -> Result<(), SecretStoreError> {
        if secret.expose().len() > WINDOWS_BLOB_LIMIT {
            return Err(SecretStoreError::TooLarge {
                limit: WINDOWS_BLOB_LIMIT,
            });
        }
        self.in_order(|| {
            self.entry(key)?
                .set_secret(secret.expose().as_bytes())
                .map_err(|error| translate(&error))
        })
    }

    fn load(&self, key: &SecretKey) -> Result<Option<Secret>, SecretStoreError> {
        self.in_order(|| match self.entry(key)?.get_secret() {
            Ok(bytes) => String::from_utf8(bytes)
                .map(|text| Some(Secret::new(text)))
                .map_err(|_| SecretStoreError::Refused("the stored secret is not text".into())),
            Err(keyring_core::Error::NoEntry) => Ok(None),
            Err(error) => Err(translate(&error)),
        })
    }

    fn delete(&self, key: &SecretKey) -> Result<(), SecretStoreError> {
        self.in_order(|| match self.entry(key)?.delete_credential() {
            Ok(()) | Err(keyring_core::Error::NoEntry) => Ok(()),
            Err(error) => Err(translate(&error)),
        })
    }
}

/// A crate error as one of ours, without any bytes it carries.
fn translate(error: &keyring_core::Error) -> SecretStoreError {
    use keyring_core::Error as E;
    match error {
        E::NoStorageAccess(_) => SecretStoreError::Denied,
        E::TooLong(_, limit) => SecretStoreError::TooLarge {
            limit: *limit as usize,
        },
        E::BadEncoding(_) | E::BadDataFormat(..) => {
            SecretStoreError::Refused("the stored secret is malformed".into())
        }
        E::NoDefaultStore => SecretStoreError::Unavailable,
        E::PlatformFailure(_) => SecretStoreError::Refused("Credential Manager failed".into()),
        _ => SecretStoreError::Refused("Credential Manager refused".into()),
    }
}
