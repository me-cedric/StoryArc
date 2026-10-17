//! Sealed secrets (`library-portability`, *Secrets travel only sealed, and only when asked*),
//! mirrored from StoryArcKit's `LibrarySecretSealer` and checked against the vector in
//! `packages/test-fixtures/library/sealed-secrets.json`, which neither app made.
//!
//! PBKDF2-HMAC-SHA256 derives a 32-byte key from the passphrase, normalised to NFC first, and
//! a 16-byte salt. Each secret is sealed with AES-256-GCM under that key with its own 12-byte
//! nonce; the ciphertext carries the 16-byte tag after it. Opening is all or nothing.

use std::collections::BTreeMap;

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use icu::normalizer::ComposingNormalizerBorrowed;
use sha2::Sha256;

use super::document::{LibrarySecrets, SealedSecret};
use crate::secrets::Secret;

pub const KDF: &str = "PBKDF2-HMAC-SHA256";
pub const CIPHER: &str = "AES-256-GCM";
/// OWASP's figure when the phones chose it; always what the writer uses.
pub const ITERATIONS: u32 = 600_000;
/// The most a document may ask for: a document is untrusted, and four billion is a hang.
pub const MAXIMUM_ITERATIONS: u32 = 10_000_000;

const SALT: usize = 16;
const NONCE: usize = 12;
const TAG: usize = 16;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SealingFailure {
    EmptyPassphrase,
    /// A KDF, a cipher or an iteration count this build does not use.
    Unsupported,
    /// A field that is not base64 or has the wrong length.
    Malformed,
    /// The passphrase is wrong or a byte changed; GCM cannot tell which.
    WrongPassphraseOrDamaged,
    /// The system gave no randomness.
    NoRandomness,
}

impl std::fmt::Display for SealingFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::EmptyPassphrase => "the passphrase is empty",
            Self::Unsupported => "the secrets are sealed in a way this app does not read",
            Self::Malformed => "the sealed secrets are damaged",
            Self::WrongPassphraseOrDamaged => "the passphrase did not open the secrets",
            Self::NoRandomness => "the system gave no randomness to seal with",
        })
    }
}

impl std::error::Error for SealingFailure {}

fn key(passphrase: &Secret, salt: &[u8], iterations: u32) -> Result<Aes256Gcm, SealingFailure> {
    let normalised = ComposingNormalizerBorrowed::new_nfc().normalize(passphrase.expose());
    if normalised.is_empty() {
        return Err(SealingFailure::EmptyPassphrase);
    }
    let mut key = [0u8; 32];
    pbkdf2::pbkdf2_hmac::<Sha256>(normalised.as_bytes(), salt, iterations, &mut key);
    Aes256Gcm::new_from_slice(&key).map_err(|_| SealingFailure::Malformed)
}

fn random(count: usize) -> Result<Vec<u8>, SealingFailure> {
    let mut bytes = vec![0u8; count];
    getrandom::fill(&mut bytes).map_err(|_| SealingFailure::NoRandomness)?;
    Ok(bytes)
}

/// Seals each secret, by source id, with a fresh salt and a fresh nonce each.
pub fn seal(
    secrets: &BTreeMap<String, Secret>,
    passphrase: &Secret,
) -> Result<LibrarySecrets, SealingFailure> {
    let nonces = secrets
        .keys()
        .map(|id| random(NONCE).map(|n| (id.clone(), n)))
        .collect::<Result<BTreeMap<_, _>, _>>()?;
    seal_with(secrets, passphrase, &random(SALT)?, &nonces)
}

/// The same with the salt and nonces given, which is how the fixed vector is checked.
pub fn seal_with(
    secrets: &BTreeMap<String, Secret>,
    passphrase: &Secret,
    salt: &[u8],
    nonces: &BTreeMap<String, Vec<u8>>,
) -> Result<LibrarySecrets, SealingFailure> {
    let cipher = key(passphrase, salt, ITERATIONS)?;
    let mut sealed = BTreeMap::new();
    for (id, secret) in secrets {
        let nonce_bytes = nonces
            .get(id)
            .filter(|n| n.len() == NONCE)
            .ok_or(SealingFailure::Malformed)?;
        let nonce =
            Nonce::try_from(nonce_bytes.as_slice()).map_err(|_| SealingFailure::Malformed)?;
        let combined = cipher
            .encrypt(&nonce, secret.expose().as_bytes())
            .map_err(|_| SealingFailure::Malformed)?;
        sealed.insert(
            id.to_ascii_lowercase(),
            SealedSecret {
                nonce: STANDARD.encode(nonce_bytes),
                ciphertext: STANDARD.encode(combined),
            },
        );
    }
    Ok(LibrarySecrets {
        kdf: KDF.into(),
        iterations: ITERATIONS,
        salt: STANDARD.encode(salt),
        cipher: CIPHER.into(),
        sealed,
    })
}

/// Every secret by source id, lower case, or the reason none opened.
pub fn open(
    secrets: &LibrarySecrets,
    passphrase: &Secret,
) -> Result<BTreeMap<String, Secret>, SealingFailure> {
    if secrets.kdf != KDF
        || secrets.cipher != CIPHER
        || !(1..=MAXIMUM_ITERATIONS).contains(&secrets.iterations)
    {
        return Err(SealingFailure::Unsupported);
    }
    let salt = STANDARD
        .decode(&secrets.salt)
        .ok()
        .filter(|s| !s.is_empty())
        .ok_or(SealingFailure::Malformed)?;
    let cipher = key(passphrase, &salt, secrets.iterations)?;
    let mut opened = BTreeMap::new();
    for (id, entry) in &secrets.sealed {
        let id = crate::shelves::shelf_id(id).ok_or(SealingFailure::Malformed)?;
        let nonce_bytes = STANDARD
            .decode(&entry.nonce)
            .ok()
            .filter(|n| n.len() == NONCE)
            .ok_or(SealingFailure::Malformed)?;
        let combined = STANDARD
            .decode(&entry.ciphertext)
            .ok()
            .filter(|c| c.len() >= TAG)
            .ok_or(SealingFailure::Malformed)?;
        let nonce =
            Nonce::try_from(nonce_bytes.as_slice()).map_err(|_| SealingFailure::Malformed)?;
        let plain = cipher
            .decrypt(&nonce, combined.as_slice())
            .map_err(|_| SealingFailure::WrongPassphraseOrDamaged)?;
        let text =
            String::from_utf8(plain).map_err(|_| SealingFailure::WrongPassphraseOrDamaged)?;
        opened.insert(id, Secret::from(text));
    }
    Ok(opened)
}
