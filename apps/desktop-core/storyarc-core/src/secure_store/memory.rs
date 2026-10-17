//! Stores that live in memory: one for tests, and the stand-in for a system with none.

use std::collections::HashMap;
use std::sync::Mutex;

use super::{Availability, SecretKey, SecretStore, SecretStoreError};
use crate::secrets::Secret;

/// A store in memory, gone with the process. The tests' store, with switches for the two
/// behaviours a real store has that matter here: a size limit and a refusal.
#[derive(Default)]
pub struct MemorySecretStore {
    items: Mutex<HashMap<SecretKey, Secret>>,
    limit: Option<usize>,
    refuses: bool,
}

impl MemorySecretStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// A store that keeps at most `limit` bytes a secret, as Credential Manager does.
    pub fn with_limit(limit: usize) -> Self {
        Self {
            limit: Some(limit),
            ..Self::default()
        }
    }

    /// A store that refuses every write, as a locked keyring or a denied prompt does.
    pub fn refusing() -> Self {
        Self {
            refuses: true,
            ..Self::default()
        }
    }

    fn items(&self) -> std::sync::MutexGuard<'_, HashMap<SecretKey, Secret>> {
        self.items
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

impl SecretStore for MemorySecretStore {
    fn availability(&self) -> Availability {
        Availability::Available
    }

    fn save(&self, key: &SecretKey, secret: &Secret) -> Result<(), SecretStoreError> {
        if self.refuses {
            return Err(SecretStoreError::Refused("the store is locked".into()));
        }
        if let Some(limit) = self.limit
            && secret.expose().len() > limit
        {
            return Err(SecretStoreError::TooLarge { limit });
        }
        self.items().insert(key.clone(), secret.clone());
        Ok(())
    }

    fn load(&self, key: &SecretKey) -> Result<Option<Secret>, SecretStoreError> {
        Ok(self.items().get(key).cloned())
    }

    fn delete(&self, key: &SecretKey) -> Result<(), SecretStoreError> {
        self.items().remove(key);
        Ok(())
    }
}

/// The system has no store running: nothing is written, ever.
#[derive(Debug, Default)]
pub struct UnavailableStore;

impl UnavailableStore {
    pub fn new() -> Self {
        Self
    }
}

impl SecretStore for UnavailableStore {
    fn availability(&self) -> Availability {
        Availability::Unavailable
    }

    fn save(&self, _: &SecretKey, _: &Secret) -> Result<(), SecretStoreError> {
        Err(SecretStoreError::Unavailable)
    }

    fn load(&self, _: &SecretKey) -> Result<Option<Secret>, SecretStoreError> {
        Ok(None)
    }

    fn delete(&self, _: &SecretKey) -> Result<(), SecretStoreError> {
        Ok(())
    }
}
