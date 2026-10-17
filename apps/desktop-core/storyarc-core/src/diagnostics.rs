//! The diagnostic export's text and its redaction (`settings-and-about`; `desktop-experience`,
//! *Exporting a diagnostic to a file*: "every credential, token and server hostname is
//! redacted as on a phone").
//!
//! [`redact`] mirrors StoryArcKit's `DiagnosticRedaction` and Android's: the same five rules
//! in the same order, over-redacting on purpose. A desktop adds two things a phone does not
//! need: Windows home folders (`C:\Users\name`) go the way `/Users/name` does, and
//! [`DiagnosticReport::render`] first removes every secret the app holds, in each encoding a
//! secret travels in, before the rules run — so a secret that arrives with no key naming it
//! and shorter than the opaque-run rule still leaves.
//!
//! The report itself carries no free text by design, as the phones' does: a source is a count,
//! never a name, because the name a reader gives a server is its hostname.

use std::sync::OnceLock;

use regex_lite::{Captures, Regex};

use crate::secrets::Secret;

/// What replaces a removed value, named so a reader sees what kind of thing went.
pub mod marker {
    pub const CREDENTIAL: &str = "[redacted]";
    pub const HOST: &str = "[host]";
    pub const TOKEN: &str = "[token]";
    pub const HOME: &str = "~";
}

fn rule(slot: &'static OnceLock<Regex>, pattern: &str) -> &'static Regex {
    slot.get_or_init(|| Regex::new(pattern).expect("the redaction patterns are fixed"))
}

/// Applies every rule, in the phones' order.
pub fn redact(text: &str) -> String {
    static AUTHORITY: OnceLock<Regex> = OnceLock::new();
    static ADDRESS: OnceLock<Regex> = OnceLock::new();
    static KEYED: OnceLock<Regex> = OnceLock::new();
    static OPAQUE: OnceLock<Regex> = OnceLock::new();
    static HOME: OnceLock<Regex> = OnceLock::new();
    static WINDOWS_HOME: OnceLock<Regex> = OnceLock::new();

    // Rule 1: the whole authority of a URL in one step, so no part of it is left behind.
    let text = rule(&AUTHORITY, r"([a-zA-Z][a-zA-Z0-9+.\-]*://)[^/\s?#]*")
        .replace_all(text, |caps: &Captures<'_>| {
            format!("{}{}", &caps[1], marker::HOST)
        });
    // Rule 2: a bare IPv4 address.
    let text =
        rule(&ADDRESS, r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b").replace_all(&text, marker::HOST);
    // Rule 3: a value introduced by a word that means "secret". The key is kept.
    let text = rule(
        &KEYED,
        r"(?i)\b(token|password|passwd|secret|key|apikey|api_key|auth|authorization|bearer)\b[\s=:]+\S+",
    )
    .replace_all(&text, |caps: &Captures<'_>| {
        format!("{}={}", &caps[1], marker::CREDENTIAL)
    });
    // Rule 4: a long unbroken run of token-shaped characters.
    let text = rule(&OPAQUE, r"\b[A-Za-z0-9+/_\-]{32,}\b").replace_all(&text, marker::TOKEN);
    // Rule 5: the home folder, which carries the reader's name; and its Windows spelling.
    let text = rule(&HOME, r"/(?:Users|home)/[^/\s]+").replace_all(&text, marker::HOME);
    rule(&WINDOWS_HOME, r"(?i)[A-Z]:\\Users\\[^\\\s]+")
        .replace_all(&text, marker::HOME)
        .into_owned()
}

/// Removes each of `secrets` from `text` as UTF-8, percent-encoded, Base64 and hex.
pub fn without_secrets(text: &str, secrets: &[&Secret]) -> String {
    let mut text = text.to_owned();
    for secret in secrets.iter().filter(|secret| !secret.is_empty()) {
        for form in forms(secret.expose()) {
            if !form.is_empty() {
                text = text.replace(&form, marker::CREDENTIAL);
            }
        }
    }
    text
}

/// The textual forms a secret takes in a URL, a header or a dump.
fn forms(secret: &str) -> Vec<String> {
    let bytes = secret.as_bytes();
    let percent: String = bytes
        .iter()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-._~".contains(b) {
                (*b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect();
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    vec![
        secret.to_owned(),
        percent.clone(),
        percent.to_lowercase(),
        base64(bytes),
        base64(bytes).trim_end_matches('=').to_owned(),
        hex.to_uppercase(),
        hex,
    ]
}

fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = chunk
            .iter()
            .enumerate()
            .fold(0u32, |acc, (i, b)| acc | u32::from(*b) << (16 - 8 * i));
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(ALPHABET[(n >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

/// The diagnostic's text: titled sections of `key = value` lines, as the phones write it.
#[derive(Debug, Clone, Default)]
pub struct DiagnosticReport {
    title: String,
    sections: Vec<(String, Vec<(String, String)>)>,
}

impl DiagnosticReport {
    pub fn new(title: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            sections: Vec::new(),
        }
    }

    /// Adds `[name]` with its lines, in order.
    pub fn section<'a>(
        &mut self,
        name: &str,
        lines: impl IntoIterator<Item = (&'a str, &'a str)>,
    ) -> &mut Self {
        let lines = lines
            .into_iter()
            .map(|(key, value)| (key.to_owned(), value.to_owned()))
            .collect();
        self.sections.push((name.to_owned(), lines));
        self
    }

    /// The text a reader reads before saving it: every secret the app holds removed first,
    /// then the phones' five rules.
    pub fn render(&self, secrets: &[&Secret]) -> String {
        let mut lines = vec![self.title.clone()];
        for (name, entries) in &self.sections {
            lines.push(String::new());
            lines.push(format!("[{name}]"));
            lines.extend(
                entries
                    .iter()
                    .map(|(key, value)| format!("{key} = {value}")),
            );
        }
        redact(&without_secrets(&lines.join("\n"), secrets))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_matches_the_rfc_vectors() {
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn a_short_secret_with_no_key_still_leaves() {
        let secret = Secret::new("pa ss!");
        let text = without_secrets("raw pa ss! and pa%20ss%21 and cGEgc3Mh", &[&secret]);
        assert_eq!(text, "raw [redacted] and [redacted] and [redacted]");
    }

    #[test]
    fn a_windows_home_folder_is_folded() {
        assert_eq!(redact(r"C:\Users\Ada\Comics"), r"~\Comics");
    }

    #[test]
    fn a_report_is_titled_sections_of_key_value_lines() {
        let mut report = DiagnosticReport::new("StoryArc diagnostic");
        report.section("App", [("version", "0.1.0")]);
        report.section("Sources", [("count", "2")]);
        assert_eq!(
            report.render(&[]),
            "StoryArc diagnostic\n\n[App]\nversion = 0.1.0\n\n[Sources]\ncount = 2"
        );
    }
}
