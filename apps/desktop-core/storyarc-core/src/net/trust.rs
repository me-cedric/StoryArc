//! Certificates: the system decides first, then the reader's pins (`opds-catalog`,
//! *Self-signed certificate*: "the app refuses the connection by default and explains why,
//! and offers to pin that specific certificate after showing its fingerprint").
//!
//! Mirrors StoryArcKit's `OpdsTrust`: a pin is the SHA-256 of the leaf certificate's DER, per
//! host, written as colon-separated uppercase hex — the form `openssl x509 -fingerprint
//! -sha256` prints, so a reader can compare it with what their server printed. Two states
//! rather than one: a refusal is recorded with the certificate's fingerprint so the app can
//! show it, and only an explicit [`TrustStore::pin`] turns it into an acceptance.
//!
//! A pinned certificate skips the chain and the name checks and nothing else: the handshake's
//! signatures are still verified against the pinned certificate's key.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

use rustls::DigitallySignedStruct;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::CryptoProvider;
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use sha2::{Digest, Sha256};

/// A certificate the system did not trust, as the app shows it before a pin.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UntrustedCertificate {
    pub host: String,
    /// SHA-256 of the DER, `AB:CD:…`.
    pub fingerprint: String,
    /// What the system said, for the explanation.
    pub reason: String,
}

/// The fingerprints a reader accepted, per host. Shared by every client of one app.
#[derive(Debug, Clone, Default)]
pub struct TrustStore {
    pinned: Arc<Mutex<HashMap<String, HashSet<String>>>>,
}

impl TrustStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Whether `host` has accepted `fingerprint`.
    pub fn accepts(&self, host: &str, fingerprint: &str) -> bool {
        self.with(|pinned| {
            pinned
                .get(&host.to_ascii_lowercase())
                .is_some_and(|set| set.contains(fingerprint))
        })
    }

    /// Records an acceptance. Only ever called after a reader saw the fingerprint.
    pub fn pin(&self, host: &str, fingerprint: &str) {
        self.with(|pinned| {
            pinned
                .entry(host.to_ascii_lowercase())
                .or_default()
                .insert(fingerprint.to_owned());
        });
    }

    /// Forgets every pin of `host`: what removing the source does.
    pub fn forget(&self, host: &str) {
        self.with(|pinned| pinned.remove(&host.to_ascii_lowercase()));
    }

    /// Every pin, for the app to persist beside the source records. A fingerprint is public.
    pub fn pins(&self) -> Vec<(String, String)> {
        self.with(|pinned| {
            let mut all: Vec<_> = pinned
                .iter()
                .flat_map(|(host, set)| set.iter().map(|fp| (host.clone(), fp.clone())))
                .collect();
            all.sort();
            all
        })
    }

    fn with<T>(&self, body: impl FnOnce(&mut HashMap<String, HashSet<String>>) -> T) -> T {
        let mut pinned = self
            .pinned
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        body(&mut pinned)
    }
}

/// SHA-256 of a certificate's DER, colon-separated uppercase hex.
pub fn fingerprint(der: &[u8]) -> String {
    Sha256::digest(der)
        .iter()
        .map(|byte| format!("{byte:02X}"))
        .collect::<Vec<_>>()
        .join(":")
}

/// The refusals of one client, by host, until the app asks for them.
pub(crate) type Refusals = Arc<Mutex<HashMap<String, UntrustedCertificate>>>;

/// The system's verifier, with the reader's pins in front of it.
#[derive(Debug)]
pub(crate) struct PinningVerifier {
    system: Arc<dyn ServerCertVerifier>,
    provider: Arc<CryptoProvider>,
    trust: TrustStore,
    refusals: Refusals,
}

impl PinningVerifier {
    pub(crate) fn new(
        system: Arc<dyn ServerCertVerifier>,
        provider: Arc<CryptoProvider>,
        trust: TrustStore,
        refusals: Refusals,
    ) -> Self {
        Self {
            system,
            provider,
            trust,
            refusals,
        }
    }
}

impl ServerCertVerifier for PinningVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &ServerName<'_>,
        ocsp_response: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        let host = server_name.to_str().to_ascii_lowercase();
        let print = fingerprint(end_entity.as_ref());
        if self.trust.accepts(&host, &print) {
            return Ok(ServerCertVerified::assertion());
        }
        self.system
            .verify_server_cert(end_entity, intermediates, server_name, ocsp_response, now)
            .inspect_err(|error| {
                let refusal = UntrustedCertificate {
                    host: host.clone(),
                    fingerprint: print.clone(),
                    reason: error.to_string(),
                };
                self.refusals
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .insert(host.clone(), refusal);
            })
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.provider
            .signature_verification_algorithms
            .supported_schemes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_fingerprint_is_colon_separated_uppercase_sha256() {
        let print = fingerprint(b"abc");
        assert_eq!(
            print,
            "BA:78:16:BF:8F:01:CF:EA:41:41:40:DE:5D:AE:22:23:B0:03:61:A3:96:17:7A:9C:B4:10:FF:61:F2:00:15:AD"
        );
    }

    #[test]
    fn a_pin_is_per_host_and_forgotten_with_it() {
        let trust = TrustStore::new();
        trust.pin("NAS.local", "AA:BB");
        assert!(trust.accepts("nas.local", "AA:BB"));
        assert!(!trust.accepts("other.local", "AA:BB"));
        assert!(!trust.accepts("nas.local", "CC:DD"));
        assert_eq!(trust.pins(), [("nas.local".to_owned(), "AA:BB".to_owned())]);
        trust.forget("nas.local");
        assert!(!trust.accepts("nas.local", "AA:BB"));
    }
}
