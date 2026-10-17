//! Linux: Secret Service on the host, the Secret portal's encrypted file keyring inside a
//! Flatpak, through `oo7` on the core's tokio runtime (design.md, Decision 7 and Open
//! Question 5).
//!
//! `oo7::Keyring::new` picks the backend itself: sandboxed, it asks the portal for the key of
//! a file keyring in the app's own data; on the host, it talks to whichever daemon owns
//! `org.freedesktop.secrets` (GNOME Keyring, KWallet, KeePassXC, oo7-daemon). When neither
//! answers — a bare Hyprland session, a minimal install — [`SecretServiceStore::connect`]
//! fails and [`system_store`](super::system_store) hands the app the session-only store.
//!
//! Items carry two attributes, the service and the account, and a label a person reading
//! their keyring understands. The label never holds the secret or a hostname. No `oo7` error
//! is formatted with `{:?}`, and the crate's `tracing` feature is off.
//!
//! Compiled on Linux only; run by the distro containers of `container-build.sh`, which have
//! no Secret Service either, so they exercise the unavailable path.

use std::collections::HashMap;

use super::{Availability, SERVICE, SecretKey, SecretStore, SecretStoreError};
use crate::runtime::{InRuntime, Runtime};
use crate::secrets::Secret;

/// The default collection of the Secret Service, or the portal's file keyring.
pub struct SecretServiceStore {
    runtime: Runtime,
    /// Dropped inside the runtime: zbus ends its connection with a task of its own.
    keyring: InRuntime<oo7::Keyring>,
}

impl SecretServiceStore {
    /// Connects, or fails with [`SecretStoreError::Unavailable`] when nothing answers.
    pub fn connect(runtime: &Runtime) -> Result<Self, SecretStoreError> {
        let keyring = runtime
            .block_on(oo7::Keyring::new())
            .map_err(|_| SecretStoreError::Unavailable)?;
        Ok(Self {
            runtime: runtime.clone(),
            keyring: InRuntime::new(runtime, keyring),
        })
    }

    fn attributes(key: &SecretKey) -> HashMap<&'static str, String> {
        HashMap::from([
            ("service", SERVICE.to_owned()),
            ("account", key.account().to_owned()),
        ])
    }
}

impl SecretStore for SecretServiceStore {
    fn availability(&self) -> Availability {
        Availability::Available
    }

    fn save(&self, key: &SecretKey, secret: &Secret) -> Result<(), SecretStoreError> {
        let attributes = Self::attributes(key);
        self.runtime.block_on(async {
            self.keyring
                .unlock()
                .await
                .map_err(|_| SecretStoreError::Denied)?;
            self.keyring
                .create_item(
                    "StoryArc source sign-in",
                    &attributes,
                    oo7::Secret::text(secret.expose()),
                    true,
                )
                .await
                .map_err(|_| SecretStoreError::Refused("the keyring refused the item".into()))
        })
    }

    fn load(&self, key: &SecretKey) -> Result<Option<Secret>, SecretStoreError> {
        let attributes = Self::attributes(key);
        self.runtime.block_on(async {
            let items = self.keyring.search_items(&attributes).await.map_err(|_| {
                SecretStoreError::Refused("the keyring could not be searched".into())
            })?;
            let Some(item) = items.first() else {
                return Ok(None);
            };
            item.unlock().await.map_err(|_| SecretStoreError::Denied)?;
            let secret = item
                .secret()
                .await
                .map_err(|_| SecretStoreError::Refused("the item could not be read".into()))?;
            String::from_utf8(secret.as_bytes().to_vec())
                .map(|text| Some(Secret::new(text)))
                .map_err(|_| SecretStoreError::Refused("the stored secret is not text".into()))
        })
    }

    fn delete(&self, key: &SecretKey) -> Result<(), SecretStoreError> {
        let attributes = Self::attributes(key);
        self.runtime.block_on(async {
            self.keyring
                .delete(&attributes)
                .await
                .map_err(|_| SecretStoreError::Refused("the keyring refused the removal".into()))
        })
    }
}
