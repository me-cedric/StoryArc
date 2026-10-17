//! OPDS catalogues (task 3.4 of `desktop-clients`; `opds-catalog`), mirrored from
//! StoryArcKit's `Catalogue` module and asserted against its parsing expectations
//! (`tests/opds.rs`) and against `pnpm opds`.
//!
//! - Both dialects, detected from the body ([`document::parse`]).
//! - What arrived instead of a feed is named: an HTML page, an empty body, a status, a
//!   redirect that could not be followed ([`OpdsError`]).
//! - A 401 names the scheme to prompt for; the credential then goes only to the catalogue's
//!   own origin, and an `https` catalogue never follows a link to `http` ([`crate::net`]).
//! - A certificate the system does not trust is refused with its fingerprint; the reader may
//!   pin it, and the next fetch is accepted ([`crate::net::trust`]).
//! - Search asks the server when the feed offers a template or an OpenSearch description,
//!   and says so when it does not ([`SearchOutcome`]).

mod atom;
pub mod document;
mod json;
mod model;

pub use document::{address_from_typed, fill_search, open_search_template, parse};
pub use model::{
    AcquisitionKind, OpdsAcquisition, OpdsEntry, OpdsFacet, OpdsFeed, OpdsGroup, OpdsSection,
    OpdsVersion,
};

use std::fmt;

use crate::net::{
    Challenge, Credential, HttpClient, HttpError, Origin, Request, Response, UntrustedCertificate,
    Url,
};

/// The media types a catalogue request accepts, both dialects first.
const ACCEPT: &str = "application/opds+json, application/atom+xml;profile=opds-catalog, \
                      application/atom+xml, application/json;q=0.9, */*;q=0.5";

/// What arrived where a feed was expected.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Received {
    Html,
    /// Something else, with its content type when the server sent one.
    Unrecognised(Option<String>),
}

/// Why a catalogue page could not be shown. Each case is one the app words for the reader.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpdsError {
    /// A 200 with nothing in it.
    Empty,
    NotAFeed(Received),
    /// A body in a dialect's shape that would not parse.
    Malformed(String),
    /// A status other than success, named: a 404 is not a generic failure.
    Http(u16),
    /// A 401, with the scheme to prompt for.
    Unauthorized(Option<Challenge>),
    /// The certificate is not trusted; the fingerprint is what a reader may pin.
    Untrusted(UntrustedCertificate),
    /// A link or redirect from `https` to `http`, not followed.
    Downgrade,
    /// An address the app does not fetch.
    RefusedAddress,
    /// Redirected too often, or to nowhere.
    Redirect,
    /// The server did not answer. Grey, never red.
    Unreachable(String),
}

impl OpdsError {
    /// Whether trying again later may succeed.
    pub fn is_transient(&self) -> bool {
        match self {
            Self::Http(status) => *status >= 500 || *status == 408 || *status == 429,
            Self::Empty | Self::Unreachable(_) => true,
            _ => false,
        }
    }
}

impl fmt::Display for OpdsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Empty => f.write_str("the server sent an empty page"),
            Self::NotAFeed(Received::Html) => {
                f.write_str("the address is a web page, not a catalogue")
            }
            Self::NotAFeed(Received::Unrecognised(Some(kind))) => {
                write!(f, "the address sent {kind}, not a catalogue")
            }
            Self::NotAFeed(Received::Unrecognised(None)) => {
                f.write_str("the address sent something that is not a catalogue")
            }
            Self::Malformed(reason) => write!(f, "the catalogue could not be read: {reason}"),
            Self::Http(status) => write!(f, "the server answered {status}"),
            Self::Unauthorized(_) => f.write_str("the catalogue asks to sign in"),
            Self::Untrusted(certificate) => write!(
                f,
                "{} presented a certificate this system does not trust; its fingerprint is {}",
                certificate.host, certificate.fingerprint
            ),
            Self::Downgrade => f.write_str("a link from https to http was not followed"),
            Self::RefusedAddress => f.write_str("the address is not one the app fetches"),
            Self::Redirect => {
                f.write_str("the server redirected somewhere it could not be followed")
            }
            Self::Unreachable(detail) => write!(f, "the catalogue cannot be reached: {detail}"),
        }
    }
}

impl std::error::Error for OpdsError {}

impl From<HttpError> for OpdsError {
    fn from(error: HttpError) -> Self {
        match error {
            HttpError::Untrusted(certificate) => Self::Untrusted(certificate),
            HttpError::Downgrade => Self::Downgrade,
            HttpError::RefusedAddress => Self::RefusedAddress,
            HttpError::TooManyRedirects => Self::Redirect,
            HttpError::TimedOut => Self::Unreachable("no answer in time".into()),
            HttpError::Cancelled => Self::Unreachable("cancelled".into()),
            HttpError::Unreachable(detail) | HttpError::Sink(detail) => Self::Unreachable(detail),
        }
    }
}

/// How a search ran.
#[derive(Debug, Clone, PartialEq)]
pub enum SearchOutcome {
    /// The server answered.
    Server(Box<OpdsFeed>),
    /// The catalogue offers no search: the app filters what it has cached, and says so.
    LocalOnly,
}

/// A catalogue the reader added.
#[derive(Debug, Clone)]
pub struct OpdsCatalogue {
    http: HttpClient,
    root: Url,
    origin: Origin,
    credential: Option<Credential>,
}

impl OpdsCatalogue {
    /// A catalogue at `root`, signing in to `root`'s origin with `credential`.
    pub fn new(
        http: &HttpClient,
        root: Url,
        credential: Option<Credential>,
    ) -> Result<Self, OpdsError> {
        let origin = Origin::of(&root).ok_or(OpdsError::RefusedAddress)?;
        Ok(Self {
            http: http.clone(),
            root,
            origin,
            credential,
        })
    }

    pub fn root(&self) -> &Url {
        &self.root
    }

    /// Fetches the root feed, for the add sheet's confirmation: the title and the dialect.
    pub fn validate(&self) -> Result<OpdsFeed, OpdsError> {
        self.feed(&self.root.clone())
    }

    /// One page of the catalogue.
    pub fn feed(&self, url: &Url) -> Result<OpdsFeed, OpdsError> {
        let response = self.get(url, Some(ACCEPT))?;
        parse(
            &response.body,
            response.content_type.as_deref(),
            &response.url,
        )
    }

    /// Searches the server when `feed` offers a way to, and says so when it does not.
    pub fn search(&self, feed: &OpdsFeed, terms: &str) -> Result<SearchOutcome, OpdsError> {
        let template = match (&feed.search_template, &feed.search_description) {
            (Some(template), _) => Some(template.clone()),
            (None, Some(description)) => {
                let response = self.get(description, None)?;
                open_search_template(&response.body, &response.url)
            }
            (None, None) => None,
        };
        let Some(template) = template else {
            return Ok(SearchOutcome::LocalOnly);
        };
        let url = fill_search(&template, terms).ok_or(OpdsError::RefusedAddress)?;
        self.feed(&url)
            .map(|feed| SearchOutcome::Server(Box::new(feed)))
    }

    /// A cover or a file, whole, with the catalogue's credential where it belongs.
    pub fn bytes(&self, url: &Url) -> Result<Response, OpdsError> {
        self.get(url, None)
    }

    /// The request the downloads queue sends for `url`: signed for this catalogue's origin.
    pub fn request(&self, url: &Url) -> Request {
        Request::get(url.clone()).signed(self.origin.clone(), self.credential.clone())
    }

    fn get(&self, url: &Url, accept: Option<&'static str>) -> Result<Response, OpdsError> {
        if self.origin.downgrades(url) {
            return Err(OpdsError::Downgrade);
        }
        let mut request = self.request(url);
        request.accept = accept;
        let response = self.http.send(request)?;
        match response.status {
            200..=299 => Ok(response),
            401 => Err(OpdsError::Unauthorized(
                response.challenge.as_deref().and_then(Challenge::of),
            )),
            status => Err(OpdsError::Http(status)),
        }
    }
}
