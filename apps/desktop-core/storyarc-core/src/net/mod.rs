//! HTTP for the catalogue and server sources and for downloads.
//!
//! One client with three rules, each from `opds-catalog`, *HTTP authentication*, and mirrored
//! from StoryArcKit's `OpdsOrigin` and `OpdsRedirect`:
//!
//! - A credential is sent **only to the origin the reader configured** — scheme, host and
//!   port — on the first request and on every redirect hop; anywhere else is fetched
//!   anonymously.
//! - A redirect or link that steps **down from `https` to `http`** relative to that origin is
//!   not followed at all.
//! - A scheme other than `http` and `https` is refused.
//!
//! Redirects are therefore followed here, by hand, rather than by reqwest. Certificates go
//! through [`trust`]. Every call blocks on the core's [`Runtime`]; the `_async` forms are for
//! code already running on it.

pub mod trust;

use std::sync::{Arc, Mutex};
use std::time::Duration;

pub use reqwest::Url;
use reqwest::header::{self, HeaderMap, HeaderValue};

use crate::io::CancelToken;
use crate::runtime::Runtime;
use crate::secrets::Secret;
use trust::{PinningVerifier, Refusals};
pub use trust::{TrustStore, UntrustedCertificate, fingerprint};

/// How many redirects one request follows.
const MAX_REDIRECTS: usize = 10;
/// The user agent every request names, so a server's log can tell StoryArc apart.
const USER_AGENT: &str = concat!("StoryArc-desktop/", env!("CARGO_PKG_VERSION"));

/// Scheme, host and port: what a credential is bound to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Origin {
    pub scheme: String,
    pub host: String,
    pub port: u16,
}

impl Origin {
    /// The origin of a web address, `None` for any other scheme.
    pub fn of(url: &Url) -> Option<Self> {
        let scheme = url.scheme().to_ascii_lowercase();
        if scheme != "http" && scheme != "https" {
            return None;
        }
        Some(Self {
            host: url.host_str()?.to_ascii_lowercase(),
            port: url.port_or_known_default()?,
            scheme,
        })
    }

    /// Whether `url` is this origin.
    pub fn admits(&self, url: &Url) -> bool {
        Self::of(url).as_ref() == Some(self)
    }

    /// Whether `url` steps down from `https` to `http`.
    pub fn downgrades(&self, url: &Url) -> bool {
        self.scheme == "https" && url.scheme().eq_ignore_ascii_case("http")
    }
}

/// How a request signs in. Secrets stay [`Secret`]s until the header is written.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Credential {
    Basic {
        username: String,
        password: Secret,
    },
    Bearer(Secret),
    /// A named header, as an API key travels.
    Header {
        name: &'static str,
        value: Secret,
    },
}

impl Credential {
    fn apply(&self, headers: &mut HeaderMap) {
        let (name, value) = match self {
            Self::Basic { username, password } => (
                header::AUTHORIZATION,
                format!(
                    "Basic {}",
                    base64(format!("{username}:{}", password.expose()).as_bytes())
                ),
            ),
            Self::Bearer(token) => (header::AUTHORIZATION, format!("Bearer {}", token.expose())),
            Self::Header { name, value } => (
                header::HeaderName::from_static(name),
                value.expose().to_owned(),
            ),
        };
        if let Ok(mut value) = HeaderValue::from_str(&value) {
            value.set_sensitive(true);
            headers.insert(name, value);
        }
    }
}

/// The challenge a 401 named, as `opds-catalog` asks the app to prompt for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Challenge {
    Basic,
    Bearer,
}

impl Challenge {
    /// The scheme of a `WWW-Authenticate` value, `None` for one the app does not speak.
    pub fn of(header: &str) -> Option<Self> {
        let name = header.split_whitespace().next()?.to_ascii_lowercase();
        match name.as_str() {
            "basic" => Some(Self::Basic),
            "bearer" => Some(Self::Bearer),
            _ => None,
        }
    }
}

/// One request.
#[derive(Debug, Clone)]
pub struct Request {
    pub url: Url,
    /// The origin the reader configured, which alone receives `credential`.
    pub origin: Option<Origin>,
    pub credential: Option<Credential>,
    /// `bytes=start-end`, `end` inclusive and absent for "to the end".
    pub range: Option<(u64, Option<u64>)>,
    /// The validator a resumed range must still match (`If-Range`).
    pub if_range: Option<String>,
    pub accept: Option<&'static str>,
    pub method: reqwest::Method,
    pub body: Option<(Vec<u8>, &'static str)>,
}

impl Request {
    pub fn get(url: Url) -> Self {
        Self {
            url,
            origin: None,
            credential: None,
            range: None,
            if_range: None,
            accept: None,
            method: reqwest::Method::GET,
            body: None,
        }
    }

    /// Signs in to `origin` with `credential`, and to nowhere else.
    pub fn signed(mut self, origin: Origin, credential: Option<Credential>) -> Self {
        self.origin = Some(origin);
        self.credential = credential;
        self
    }

    pub fn range(mut self, start: u64, end: Option<u64>) -> Self {
        self.range = Some((start, end));
        self
    }

    pub fn json_body(mut self, method: reqwest::Method, body: Vec<u8>) -> Self {
        self.method = method;
        self.body = Some((body, "application/json"));
        self
    }
}

/// What came back, with the headers the sources read.
#[derive(Debug, Clone)]
pub struct Response {
    pub status: u16,
    /// Where the last hop landed.
    pub url: Url,
    pub content_type: Option<String>,
    pub etag: Option<String>,
    pub content_range: Option<String>,
    pub content_length: Option<u64>,
    pub accepts_ranges: bool,
    pub challenge: Option<String>,
    pub body: Vec<u8>,
}

impl Response {
    pub fn is_success(&self) -> bool {
        (200..300).contains(&self.status)
    }

    /// The total length a `206`'s `Content-Range` names.
    pub fn range_total(&self) -> Option<u64> {
        self.content_range
            .as_deref()?
            .rsplit('/')
            .next()?
            .parse()
            .ok()
    }

    /// The start a `206`'s `Content-Range` names.
    pub fn range_start(&self) -> Option<u64> {
        let spec = self.content_range.as_deref()?.strip_prefix("bytes ")?;
        spec.split('-').next()?.parse().ok()
    }
}

/// Why a request got no answer to read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HttpError {
    /// Nothing answered, the name did not resolve, or the connection dropped.
    Unreachable(String),
    /// The answer did not arrive in time.
    TimedOut,
    /// The system did not trust the certificate and no pin accepts it.
    Untrusted(UntrustedCertificate),
    /// A redirect or link from `https` to `http`, never followed.
    Downgrade,
    /// An address the app does not fetch: another scheme, or a location that is not one.
    RefusedAddress,
    /// More than ten redirects.
    TooManyRedirects,
    /// The caller's token fired.
    Cancelled,
    /// A body the caller's sink refused, such as a full disk.
    Sink(String),
}

impl std::fmt::Display for HttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unreachable(detail) => write!(f, "the server cannot be reached: {detail}"),
            Self::TimedOut => f.write_str("the server did not answer in time"),
            Self::Untrusted(cert) => write!(
                f,
                "{} presented a certificate this system does not trust ({}); fingerprint {}",
                cert.host, cert.reason, cert.fingerprint
            ),
            Self::Downgrade => f.write_str("a link from https to http was not followed"),
            Self::RefusedAddress => f.write_str("the address is not one the app fetches"),
            Self::TooManyRedirects => f.write_str("the server redirected too many times"),
            Self::Cancelled => f.write_str("cancelled"),
            Self::Sink(detail) => write!(f, "the download could not be written: {detail}"),
        }
    }
}

impl std::error::Error for HttpError {}

/// The client every network source shares.
#[derive(Clone)]
pub struct HttpClient {
    runtime: Runtime,
    client: reqwest::Client,
    refusals: Refusals,
    trust: TrustStore,
}

impl std::fmt::Debug for HttpClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("HttpClient")
    }
}

impl HttpClient {
    /// A client that trusts what the system trusts, and what `trust` pins.
    pub fn new(runtime: &Runtime, trust: TrustStore) -> Result<Self, HttpError> {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let system = rustls_platform_verifier::Verifier::new(Arc::clone(&provider))
            .map_err(|error| HttpError::Unreachable(format!("no system trust store: {error}")))?;
        let refusals: Refusals = Arc::new(Mutex::new(Default::default()));
        let verifier = PinningVerifier::new(
            Arc::new(system),
            Arc::clone(&provider),
            trust.clone(),
            Arc::clone(&refusals),
        );
        let tls = rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .map_err(|error| HttpError::Unreachable(error.to_string()))?
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(verifier))
            .with_no_client_auth();
        let client = reqwest::Client::builder()
            .tls_backend_preconfigured(tls)
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(10))
            .read_timeout(Duration::from_secs(30))
            .user_agent(USER_AGENT)
            .build()
            .map_err(|error| HttpError::Unreachable(error.to_string()))?;
        Ok(Self {
            runtime: runtime.clone(),
            client,
            refusals,
            trust,
        })
    }

    pub fn trust(&self) -> &TrustStore {
        &self.trust
    }

    pub fn runtime(&self) -> &Runtime {
        &self.runtime
    }

    /// Sends `request`, following redirects by the rules above, and reads the whole body.
    pub fn send(&self, request: Request) -> Result<Response, HttpError> {
        self.runtime.block_on(self.send_async(request))
    }

    pub async fn send_async(&self, request: Request) -> Result<Response, HttpError> {
        let mut body = Vec::new();
        let mut response = self
            .stream_async(
                request,
                &CancelToken::new(),
                |_| Ok(()),
                |chunk| {
                    body.extend_from_slice(chunk);
                    Ok(())
                },
            )
            .await?;
        response.body = body;
        Ok(response)
    }

    /// Sends `request`, shows `head` the status and headers before any byte of the body, and
    /// hands the body to `sink` as it arrives, for downloads. Either may refuse with a reason,
    /// which ends the transfer as [`HttpError::Sink`]. The returned response carries the
    /// headers and an empty body.
    pub fn stream(
        &self,
        request: Request,
        cancel: &CancelToken,
        head: impl FnOnce(&Response) -> Result<(), String>,
        sink: impl FnMut(&[u8]) -> Result<(), String>,
    ) -> Result<Response, HttpError> {
        self.runtime
            .block_on(self.stream_async(request, cancel, head, sink))
    }

    pub async fn stream_async(
        &self,
        request: Request,
        cancel: &CancelToken,
        head: impl FnOnce(&Response) -> Result<(), String>,
        mut sink: impl FnMut(&[u8]) -> Result<(), String>,
    ) -> Result<Response, HttpError> {
        let mut head = Some(head);
        let mut url = request.url.clone();
        let started = Origin::of(&url).ok_or(HttpError::RefusedAddress)?;
        let bound = request.origin.clone().unwrap_or(started);
        for _ in 0..=MAX_REDIRECTS {
            if cancel.is_cancelled() {
                return Err(HttpError::Cancelled);
            }
            if Origin::of(&url).is_none() {
                return Err(HttpError::RefusedAddress);
            }
            if bound.downgrades(&url) {
                return Err(HttpError::Downgrade);
            }
            let reply = self
                .client
                .request(request.method.clone(), url.clone())
                .headers(self.headers(&request, &bound, &url))
                .body(
                    request
                        .body
                        .as_ref()
                        .map(|(b, _)| b.clone())
                        .unwrap_or_default(),
                )
                .send()
                .await
                .map_err(|error| self.failure(&error, &url))?;
            let status = reply.status().as_u16();
            if (300..400).contains(&status) && status != 304 {
                let location = reply
                    .headers()
                    .get(header::LOCATION)
                    .and_then(|value| value.to_str().ok())
                    .ok_or(HttpError::RefusedAddress)?;
                url = url.join(location).map_err(|_| HttpError::RefusedAddress)?;
                continue;
            }
            let mut response = Response {
                status,
                url: url.clone(),
                content_type: text(reply.headers(), header::CONTENT_TYPE),
                etag: text(reply.headers(), header::ETAG),
                content_range: text(reply.headers(), header::CONTENT_RANGE),
                content_length: reply.content_length(),
                accepts_ranges: text(reply.headers(), header::ACCEPT_RANGES)
                    .is_some_and(|value| value.eq_ignore_ascii_case("bytes")),
                challenge: text(reply.headers(), header::WWW_AUTHENTICATE),
                body: Vec::new(),
            };
            if let Some(head) = head.take() {
                head(&response).map_err(HttpError::Sink)?;
            }
            let mut reply = reply;
            loop {
                if cancel.is_cancelled() {
                    return Err(HttpError::Cancelled);
                }
                match reply.chunk().await {
                    Ok(Some(chunk)) => sink(&chunk).map_err(HttpError::Sink)?,
                    Ok(None) => break,
                    Err(error) => return Err(self.failure(&error, &url)),
                }
            }
            response.body = Vec::new();
            return Ok(response);
        }
        Err(HttpError::TooManyRedirects)
    }

    fn headers(&self, request: &Request, bound: &Origin, url: &Url) -> HeaderMap {
        let mut headers = HeaderMap::new();
        if let Some(accept) = request.accept {
            headers.insert(header::ACCEPT, HeaderValue::from_static(accept));
        }
        if let Some((_, content_type)) = &request.body {
            headers.insert(header::CONTENT_TYPE, HeaderValue::from_static(content_type));
        }
        if let Some((start, end)) = request.range {
            let range = match end {
                Some(end) => format!("bytes={start}-{end}"),
                None => format!("bytes={start}-"),
            };
            if let Ok(value) = HeaderValue::from_str(&range) {
                headers.insert(header::RANGE, value);
            }
        }
        if let Some(tag) = &request.if_range
            && let Ok(value) = HeaderValue::from_str(tag)
        {
            headers.insert(header::IF_RANGE, value);
        }
        if let Some(credential) = &request.credential
            && bound.admits(url)
        {
            credential.apply(&mut headers);
        }
        headers
    }

    fn failure(&self, error: &reqwest::Error, url: &Url) -> HttpError {
        if error.is_timeout() {
            return HttpError::TimedOut;
        }
        let host = url.host_str().unwrap_or_default().to_ascii_lowercase();
        let refused = self
            .refusals
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(&host);
        if let Some(certificate) = refused {
            return HttpError::Untrusted(certificate);
        }
        // reqwest's message names the URL and the cause; a URL here carries no secret.
        let mut detail = error.to_string();
        let mut source = std::error::Error::source(error);
        while let Some(cause) = source {
            detail = format!("{detail}: {cause}");
            source = cause.source();
        }
        HttpError::Unreachable(detail)
    }
}

fn text(headers: &HeaderMap, name: header::HeaderName) -> Option<String> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned)
}

/// Standard Base64 with padding, for the Basic header.
pub(crate) fn base64(bytes: &[u8]) -> String {
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

#[cfg(test)]
mod tests {
    use super::*;

    fn url(text: &str) -> Url {
        Url::parse(text).unwrap()
    }

    #[test]
    fn an_origin_is_scheme_host_and_port_with_the_default_filled_in() {
        let origin = Origin::of(&url("https://Library.Example/opds")).unwrap();
        assert_eq!(origin.port, 443);
        assert_eq!(origin.host, "library.example");
        assert!(origin.admits(&url("https://library.example:443/files/1")));
        assert!(!origin.admits(&url("https://library.example:8443/files/1")));
        assert!(!origin.admits(&url("http://library.example/files/1")));
        assert!(origin.downgrades(&url("http://library.example/files/1")));
        assert!(Origin::of(&url("ftp://library.example/")).is_none());
    }

    #[test]
    fn a_credential_goes_to_its_origin_and_nowhere_else() {
        let client = HttpClient::new(&Runtime::new().unwrap(), TrustStore::new()).unwrap();
        let home = Origin::of(&url("http://127.0.0.1:4444/")).unwrap();
        let request = Request::get(url("http://127.0.0.1:4444/private")).signed(
            home.clone(),
            Some(Credential::Basic {
                username: "ada".into(),
                password: "lovelace".into(),
            }),
        );
        let signed = client.headers(&request, &home, &url("http://127.0.0.1:4444/x"));
        assert_eq!(
            signed.get(header::AUTHORIZATION).unwrap(),
            "Basic YWRhOmxvdmVsYWNl"
        );
        let elsewhere = client.headers(&request, &home, &url("http://cdn.example/x"));
        assert!(elsewhere.get(header::AUTHORIZATION).is_none());
    }

    #[test]
    fn a_challenge_names_its_scheme() {
        assert_eq!(
            Challenge::of("Basic realm=\"opds\""),
            Some(Challenge::Basic)
        );
        assert_eq!(Challenge::of("Bearer"), Some(Challenge::Bearer));
        assert_eq!(Challenge::of("Digest qop=auth"), None);
    }

    #[test]
    fn a_content_range_names_its_start_and_total() {
        let response = Response {
            status: 206,
            url: url("http://x/"),
            content_type: None,
            etag: None,
            content_range: Some("bytes 100-199/5000".into()),
            content_length: Some(100),
            accepts_ranges: true,
            challenge: None,
            body: Vec::new(),
        };
        assert_eq!(response.range_start(), Some(100));
        assert_eq!(response.range_total(), Some(5000));
    }
}
