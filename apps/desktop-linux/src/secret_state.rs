//! The secret store's states, in the reader's words (task 3.18; `desktop-experience`,
//! *Secrets in the system's own store*). Pure over the core's `Vault`:
//!
//! - **A service runs**: the secret is kept, nothing is said.
//! - **No service runs** (a bare Hyprland session): the secret is not written anywhere, the
//!   source works for the session with it held in memory, and one grey line says what
//!   supplies a store, once.
//! - **In a Flatpak** the core reaches the Secret portal's file keyring, kept in the app's
//!   own data; that is a store, so nothing is said except in the source's detail.
//! - **The store refuses** (a locked keyring, a denied prompt): the failure is named, no
//!   copy is kept, and the source shows as needing a sign-in.

use storyarc_core::secrets::{
    SaveOutcome, Secret, SecretKey, SecretStoreError, UNAVAILABLE_REMEDY, Vault,
};

use crate::strings::tr;

/// What saving a secret came to, for the add sheet.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Saved {
    /// In the system's store. Nothing to say.
    Kept,
    /// For this session only. `grey_line` is present the first time only.
    ThisSession { grey_line: Option<String> },
    /// The store refused. Names the failure; no copy was kept.
    Refused { text: String },
}

/// Saves `secret` under `key` and says what became of it.
pub fn save(vault: &Vault, key: &SecretKey, secret: Secret, noun: Noun) -> Saved {
    match vault.save(key, secret) {
        Ok(SaveOutcome::Stored) => Saved::Kept,
        Ok(SaveOutcome::SessionOnly { notice }) => Saved::ThisSession {
            grey_line: notice.map(|_| unavailable_line()),
        },
        Err(error) => Saved::Refused {
            text: refusal(&error, noun),
        },
    }
}

/// What the secret is called in the refusal's sentence.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Noun {
    Password,
    ApiKey,
    SignIn,
}

/// The one grey line when no store runs. The remedy comes from the core, which names the
/// services that supply one.
pub fn unavailable_line() -> String {
    tr("secrets.unavailable", UNAVAILABLE_REMEDY)
}

/// The line the Preferences storage group shows beside the secrets: what holds them now.
pub fn status_line(vault: &Vault, flatpak: bool) -> String {
    if vault.is_session_only() {
        unavailable_line()
    } else if flatpak {
        tr(
            "secrets.flatpak",
            "Passwords are kept in this app's encrypted keyring, through the desktop's Secret portal.",
        )
    } else {
        tr(
            "secrets.service",
            "Passwords are kept in your desktop's keyring.",
        )
    }
}

fn refusal(error: &SecretStoreError, noun: Noun) -> String {
    match (error, noun) {
        (SecretStoreError::Denied, _) => tr(
            "secrets.denied",
            "The keyring was not unlocked, so nothing was saved. Sign in again once it is.",
        ),
        (_, Noun::Password) => tr(
            "smb.error.keyNotStored",
            "This device would not store the password, so the share was not saved.",
        ),
        (_, Noun::ApiKey) => tr(
            "kavita.error.keyNotStored",
            "This device would not store the API key, so the server was not added. Nothing was saved half-finished.",
        ),
        (_, Noun::SignIn) => tr(
            "catalogue.error.secretNotStored",
            "This device would not store the sign-in, so the catalogue was not added. Nothing was saved half-finished.",
        ),
    }
}

/// Whether a source whose secret cannot be found shows as needing a sign-in: it holds none
/// in the session and none in the store (after a launch with no service, always).
pub fn needs_sign_in(vault: &Vault, key: &SecretKey) -> bool {
    !matches!(vault.load(key), Ok(Some(_)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use storyarc_core::secrets::{Availability, MemorySecretStore, SecretStore, UnavailableStore};

    fn key() -> SecretKey {
        SecretKey::for_source("s1", "password")
    }

    #[test]
    fn a_running_service_keeps_the_secret_and_says_nothing() {
        let vault = Vault::new(Box::new(MemorySecretStore::new()));
        let saved = save(&vault, &key(), Secret::new("pw"), Noun::Password);
        assert_eq!(saved, Saved::Kept);
        assert!(!needs_sign_in(&vault, &key()));
    }

    #[test]
    fn no_service_holds_the_secret_for_the_session_and_says_so_once_in_grey() {
        let vault = Vault::new(Box::new(UnavailableStore::new()));
        let first = save(&vault, &key(), Secret::new("pw"), Noun::Password);
        let Saved::ThisSession {
            grey_line: Some(line),
        } = first
        else {
            panic!("the first save names the remedy");
        };
        assert!(line.contains("Secret Service") || line.contains("Keyring"));
        let second = save(&vault, &key(), Secret::new("pw2"), Noun::Password);
        assert_eq!(second, Saved::ThisSession { grey_line: None });
        // The source works for the session ...
        assert_eq!(vault.load(&key()).unwrap().unwrap().expose(), "pw2");
        // ... and asks again at the next launch: a new vault holds nothing.
        let next_launch = Vault::new(Box::new(UnavailableStore::new()));
        assert!(needs_sign_in(&next_launch, &key()));
    }

    struct Refusing;
    impl SecretStore for Refusing {
        fn availability(&self) -> Availability {
            Availability::Available
        }
        fn save(&self, _: &SecretKey, _: &Secret) -> Result<(), SecretStoreError> {
            Err(SecretStoreError::Refused("no".into()))
        }
        fn load(&self, _: &SecretKey) -> Result<Option<Secret>, SecretStoreError> {
            Ok(None)
        }
        fn delete(&self, _: &SecretKey) -> Result<(), SecretStoreError> {
            Ok(())
        }
    }

    #[test]
    fn a_store_that_refuses_is_named_keeps_no_copy_and_leaves_the_source_needing_a_sign_in() {
        let vault = Vault::new(Box::new(Refusing));
        let saved = save(&vault, &key(), Secret::new("pw"), Noun::ApiKey);
        let Saved::Refused { text } = saved else {
            panic!("a refusal is named");
        };
        assert!(text.contains("API key"));
        assert!(needs_sign_in(&vault, &key()));
    }

    #[test]
    fn the_storage_line_tells_a_session_only_vault_from_a_keyring_and_a_flatpak() {
        let none = Vault::new(Box::new(UnavailableStore::new()));
        let some = Vault::new(Box::new(MemorySecretStore::new()));
        assert_eq!(status_line(&none, false), unavailable_line());
        assert_eq!(status_line(&none, true), unavailable_line());
        assert!(status_line(&some, true).contains("Secret portal"));
        assert!(status_line(&some, false).contains("keyring"));
        assert_ne!(status_line(&some, true), status_line(&some, false));
    }
}
