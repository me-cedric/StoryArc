//! Kavita servers (task 3.5 of `desktop-clients`; `kavita-server`), mirrored from
//! StoryArcKit's `Kavita` module and run against `pnpm kavita` (`scripts/kavita-server.mjs`).
//!
//! The API key signs in once (`Plugin/authenticate`) for a session token; the token rides
//! every later call as a bearer and is renewed once on a 401. The key itself goes only to the
//! sign-in and to image URLs, which Kavita authorises by query; it is a [`Secret`] throughout.
//! Progress crosses by [`exchange::KavitaExchange`], the rule all three platforms share.

pub mod exchange;

pub use exchange::{KavitaExchange, KavitaOwed};

use std::fmt;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

use crate::net::{Credential, HttpClient, HttpError, Origin, Request, Response, Url};
use crate::secrets::Secret;

/// The plugin name Kavita records for the session.
const PLUGIN: &str = "StoryArc";

/// Where a server is and the key it gave the reader.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KavitaAddress {
    /// The server's root, as typed: `https://kavita.local:5000/`.
    pub base: Url,
    pub api_key: Secret,
}

impl KavitaAddress {
    /// `https://` is assumed when a typed address names no scheme.
    pub fn parse(typed: &str, api_key: impl Into<Secret>) -> Option<Self> {
        let base = crate::sources::opds::address_from_typed(typed)?;
        Some(Self {
            base,
            api_key: api_key.into(),
        })
    }

    /// `base` + `api/<path>`, with `query`.
    fn endpoint(&self, path: &str, query: &[(&str, &str)]) -> Option<Url> {
        let mut root = self.base.clone();
        if !root.path().ends_with('/') {
            let path = format!("{}/", root.path());
            root.set_path(&path);
        }
        let mut url = root.join(&format!("api/{path}")).ok()?;
        if !query.is_empty() {
            url.query_pairs_mut().extend_pairs(query);
        }
        Some(url)
    }
}

/// Why a server could not be read. Each case is one the app words for the reader.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KavitaError {
    BadAddress,
    /// The key was refused, after one renewal.
    KeyRejected,
    /// The server is too old for a route this client calls.
    RouteMissing(String),
    /// An answer that is not what the route returns.
    UnexpectedResponse,
    Http(u16),
    /// The server did not answer. Grey, never red.
    Unreachable(String),
}

impl fmt::Display for KavitaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::BadAddress => f.write_str("the server address is not one the app can reach"),
            Self::KeyRejected => f.write_str("the server refused the API key"),
            Self::RouteMissing(path) => write!(f, "the server is too old for {path}"),
            Self::UnexpectedResponse => f.write_str("the server answered in an unexpected shape"),
            Self::Http(status) => write!(f, "the server answered {status}"),
            Self::Unreachable(detail) => write!(f, "the server cannot be reached: {detail}"),
        }
    }
}

impl std::error::Error for KavitaError {}

impl From<HttpError> for KavitaError {
    fn from(error: HttpError) -> Self {
        Self::Unreachable(error.to_string())
    }
}

/// Who the key signed in as.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KavitaIdentity {
    pub username: String,
}

/// A library on the server.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KavitaLibrary {
    pub id: i64,
    pub name: String,
}

/// A series, with its reading totals.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KavitaSeries {
    pub id: i64,
    pub name: String,
    #[serde(default)]
    pub library_id: i64,
    #[serde(default)]
    pub pages: i64,
    #[serde(default)]
    pub pages_read: i64,
}

/// A chapter: Kavita's unit of progress.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KavitaChapter {
    pub id: i64,
    #[serde(default)]
    pub number: String,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub pages: i64,
    #[serde(default)]
    pub pages_read: i64,
    #[serde(default)]
    pub files: Vec<KavitaFile>,
}

impl KavitaChapter {
    pub fn is_finished(&self) -> bool {
        self.pages > 0 && self.pages_read >= self.pages
    }

    /// The bytes the chapter's files hold, for a download's declared size.
    pub fn file_bytes(&self) -> i64 {
        self.files.iter().map(|file| file.bytes).sum()
    }

    /// The remote id a library record files this chapter under: `chapter:<id>`, as the phones.
    pub fn remote_id(&self) -> String {
        format!("chapter:{}", self.id)
    }
}

/// One file of a chapter.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KavitaFile {
    #[serde(default)]
    pub bytes: i64,
}

/// A volume and its chapters.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KavitaVolume {
    pub id: i64,
    #[serde(default)]
    pub number: i64,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub chapters: Vec<KavitaChapter>,
}

/// What `Reader/progress` takes: the page the reader is on, from zero.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KavitaPosition {
    pub library_id: i64,
    pub series_id: i64,
    pub volume_id: i64,
    pub chapter_id: i64,
    pub page_num: i64,
}

#[derive(Deserialize)]
struct Account {
    username: String,
    token: String,
}

/// A signed-in Kavita server.
#[derive(Debug)]
pub struct KavitaClient {
    http: HttpClient,
    address: KavitaAddress,
    origin: Origin,
    token: Mutex<Option<Secret>>,
}

impl KavitaClient {
    pub fn new(http: &HttpClient, address: KavitaAddress) -> Result<Self, KavitaError> {
        let origin = Origin::of(&address.base).ok_or(KavitaError::BadAddress)?;
        Ok(Self {
            http: http.clone(),
            address,
            origin,
            token: Mutex::new(None),
        })
    }

    /// Signs in with the key: what the add sheet validates before saving.
    pub fn connect(&self) -> Result<KavitaIdentity, KavitaError> {
        let username = self.authenticate()?;
        Ok(KavitaIdentity { username })
    }

    pub fn libraries(&self) -> Result<Vec<KavitaLibrary>, KavitaError> {
        self.json(self.get("Library/libraries", &[])?)
    }

    /// The series of one library, or of every library. Narrowed by a filter in the body,
    /// which is the one place Kavita reads it.
    pub fn series(&self, library: Option<i64>) -> Result<Vec<KavitaSeries>, KavitaError> {
        let body = match library {
            Some(id) => serde_json::json!({
                "statements": [{ "comparison": 0, "field": 19, "value": id.to_string() }],
                "combination": 0,
            }),
            None => serde_json::json!({}),
        };
        self.json(self.post("Series/all-v2", &[], body)?)
    }

    pub fn volumes(&self, series_id: i64) -> Result<Vec<KavitaVolume>, KavitaError> {
        self.json(self.get("Series/volumes", &[("seriesId", &series_id.to_string())])?)
    }

    /// The chapter Kavita says a reader should open next.
    pub fn continue_point(&self, series_id: i64) -> Result<KavitaChapter, KavitaError> {
        self.json(self.get(
            "Reader/continue-point",
            &[("seriesId", &series_id.to_string())],
        )?)
    }

    /// Tells the server the page the reader is on.
    pub fn report(&self, position: &KavitaPosition) -> Result<(), KavitaError> {
        let body = serde_json::to_value(position).map_err(|_| KavitaError::UnexpectedResponse)?;
        self.post("Reader/progress", &[], body).map(drop)
    }

    /// Marks a chapter read or unread: how a finished record is pushed.
    pub fn mark(&self, series_id: i64, chapter_id: i64, read: bool) -> Result<(), KavitaError> {
        let path = if read {
            "Reader/mark-multiple-read"
        } else {
            "Reader/mark-multiple-unread"
        };
        let body = serde_json::json!({
            "seriesId": series_id,
            "volumeIds": [],
            "chapterIds": [chapter_id],
            "generateReadingSession": false,
        });
        self.post(path, &[], body).map(drop)
    }

    /// Sends one owed position: a mark when finished, a page otherwise. The caller writes
    /// `owed.settled` only when this succeeds.
    pub fn push(
        &self,
        owed: &KavitaOwed,
        library_id: i64,
        series_id: i64,
        volume_id: i64,
    ) -> Result<(), KavitaError> {
        if owed.is_mark_read {
            return self.mark(series_id, owed.chapter_id, true);
        }
        self.report(&KavitaPosition {
            library_id,
            series_id,
            volume_id,
            chapter_id: owed.chapter_id,
            page_num: owed.page_num,
        })
    }

    /// The request that downloads a chapter, signed for this server only.
    pub fn chapter_request(&self, chapter_id: i64) -> Result<Request, KavitaError> {
        let url = self
            .address
            .endpoint(
                "Download/chapter",
                &[("chapterId", &chapter_id.to_string())],
            )
            .ok_or(KavitaError::BadAddress)?;
        Ok(Request::get(url).signed(self.origin.clone(), Some(self.bearer()?)))
    }

    /// A series cover's address. Kavita authorises images by the key in the query, so the URL
    /// is a secret too: the app fetches it and never shows or logs it.
    pub fn series_cover(&self, series_id: i64) -> Option<Url> {
        self.address.endpoint(
            "Image/series-cover",
            &[
                ("seriesId", &series_id.to_string()),
                ("apiKey", self.address.api_key.expose()),
            ],
        )
    }

    fn authenticate(&self) -> Result<String, KavitaError> {
        let url = self
            .address
            .endpoint(
                "Plugin/authenticate",
                &[
                    ("apiKey", self.address.api_key.expose()),
                    ("pluginName", PLUGIN),
                ],
            )
            .ok_or(KavitaError::BadAddress)?;
        let mut request = Request::get(url);
        request.method = reqwest::Method::POST;
        request.accept = Some("application/json");
        let response = self.http.send(request)?;
        match response.status {
            200..=299 => {}
            401 | 403 => return Err(KavitaError::KeyRejected),
            404 => return Err(KavitaError::RouteMissing("Plugin/authenticate".into())),
            status => return Err(KavitaError::Http(status)),
        }
        let account: Account =
            serde_json::from_slice(&response.body).map_err(|_| KavitaError::UnexpectedResponse)?;
        *self.token_slot() = Some(Secret::new(account.token));
        Ok(account.username)
    }

    fn bearer(&self) -> Result<Credential, KavitaError> {
        if self.token_slot().is_none() {
            self.authenticate()?;
        }
        self.token_slot()
            .clone()
            .map(Credential::Bearer)
            .ok_or(KavitaError::KeyRejected)
    }

    fn token_slot(&self) -> std::sync::MutexGuard<'_, Option<Secret>> {
        self.token
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    fn get(&self, path: &str, query: &[(&str, &str)]) -> Result<Response, KavitaError> {
        self.call(path, query, None)
    }

    fn post(
        &self,
        path: &str,
        query: &[(&str, &str)],
        body: serde_json::Value,
    ) -> Result<Response, KavitaError> {
        self.call(path, query, Some(body))
    }

    /// One authenticated call, renewing the token once on a 401.
    fn call(
        &self,
        path: &str,
        query: &[(&str, &str)],
        body: Option<serde_json::Value>,
    ) -> Result<Response, KavitaError> {
        let url = self
            .address
            .endpoint(path, query)
            .ok_or(KavitaError::BadAddress)?;
        for attempt in 0..2 {
            let mut request =
                Request::get(url.clone()).signed(self.origin.clone(), Some(self.bearer()?));
            request.accept = Some("application/json");
            if let Some(body) = &body {
                request = request.json_body(reqwest::Method::POST, body.to_string().into_bytes());
            }
            let response = self.http.send(request)?;
            match response.status {
                200..=299 => return Ok(response),
                401 if attempt == 0 => {
                    *self.token_slot() = None;
                }
                401 => return Err(KavitaError::KeyRejected),
                // A 404 is a missing series or chapter as often as a missing route, so it
                // stays a status here; only the sign-in names a route as missing.
                status => return Err(KavitaError::Http(status)),
            }
        }
        Err(KavitaError::KeyRejected)
    }

    fn json<T: serde::de::DeserializeOwned>(&self, response: Response) -> Result<T, KavitaError> {
        serde_json::from_slice(&response.body).map_err(|_| KavitaError::UnexpectedResponse)
    }
}
