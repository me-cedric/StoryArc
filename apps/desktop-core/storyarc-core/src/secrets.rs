//! Secrets: a password, a token, an API key, held in memory.
//!
//! [`Secret`] exists so the rule of `desktop-experience` (*Secrets in the system's own store*)
//! is kept by the compiler rather than by care. It has no `Display`, its `Debug` prints a fixed
//! mask, it does not serialise, and its bytes are overwritten when it is dropped. The one way
//! to the characters is [`Secret::expose`], which a reviewer can search for.

use std::fmt;

/// What `Debug` prints in place of a secret. Never the length, which would tell a reader of a
/// log how long the password is.
pub const REDACTED: &str = "<redacted>";

/// A secret's text, kept out of every format the core writes.
#[derive(Clone, PartialEq, Eq)]
pub struct Secret(String);

impl Secret {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    /// The secret's text, for the one call that must send it: a login, an `Authorization`
    /// header, a store write.
    pub fn expose(&self) -> &str {
        &self.0
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

impl fmt::Debug for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(REDACTED)
    }
}

impl Drop for Secret {
    fn drop(&mut self) {
        // Overwrite in place before the allocation is returned. Not a guarantee against every
        // copy the allocator or a library made, which is why the store, not memory, is where
        // a secret lives between launches.
        let mut bytes = std::mem::take(&mut self.0).into_bytes();
        bytes.iter_mut().for_each(|byte| *byte = 0);
        std::hint::black_box(&bytes);
    }
}

impl From<&str> for Secret {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}

impl From<String> for Secret {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_prints_the_mask_and_never_the_text_or_its_length() {
        let secret = Secret::new("correct horse battery staple");
        let printed = format!("{secret:?} {secret:#?}");
        assert!(!printed.contains("horse"));
        assert!(!printed.contains("28"));
        assert_eq!(printed, format!("{REDACTED} {REDACTED}"));
    }

    #[test]
    fn expose_is_the_way_to_the_text() {
        assert_eq!(Secret::from("lovelace").expose(), "lovelace");
        assert!(Secret::from("").is_empty());
    }
}
