//! Wave 3 exports for the network: the core's one runtime, the HTTP client with the reader's
//! certificate pins, SMB shares, OPDS catalogues, Kavita servers, the metered flag and a
//! download. Requests cross as UTF-8 JSON; a secret travels in a request only for the call
//! that uses it and is never written back. Every call blocks, so C# runs it on `Task.Run`.

use std::ffi::c_void;

use serde::Deserialize;
use serde_json::json;
use storyarc_core::downloads::DownloadFolder;
use storyarc_core::metered::{self, NetworkState};
use storyarc_core::net::{Credential, HttpClient, Origin, Request, TrustStore, Url};
use storyarc_core::runtime::Runtime;
use storyarc_core::secrets::Secret;
use storyarc_core::sources::kavita::{KavitaAddress, KavitaClient};
use storyarc_core::sources::opds::{OpdsCatalogue, SearchOutcome};
use storyarc_core::sources::smb::{SmbAddress, SmbLogin, SmbShare};

use crate::records::{
    self, HTTP, RUNTIME, SHARE, clear, http_failure, invalid, json_arg, kavita_failure,
    landing_failure, opds_failure, smb_failure, token, write_json,
};
use crate::seam::{borrow, guard, into_handle, release, utf8, write};
use crate::{STORYARC_ERROR_INTERNAL, StoryArcBuffer, fail};

/// Creates the core's one runtime and writes its handle to `out_runtime`; free it with
/// `storyarc_runtime_free` when the app quits.
///
/// # Safety
///
/// `out_runtime` must point to writable storage for one pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_runtime_new(out_runtime: *mut *mut c_void) -> i32 {
    guard(|| {
        // SAFETY: the caller's promise, passed on.
        unsafe { write(out_runtime, std::ptr::null_mut(), "out_runtime")? };
        let runtime = Runtime::new().map_err(|e| fail(STORYARC_ERROR_INTERNAL, &e.to_string()))?;
        // SAFETY: checked writable above.
        unsafe { out_runtime.write(into_handle(RUNTIME, runtime)) };
        Ok(())
    })
}

/// Releases the runtime. Null is ignored.
///
/// # Safety
///
/// `runtime` must be null or a live runtime handle, released once, after every handle made
/// from it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_runtime_free(runtime: *mut c_void) {
    // SAFETY: the caller's promise, passed on.
    unsafe { release::<Runtime>(runtime, RUNTIME) };
}

/// Creates the HTTP client every catalogue, server and download shares, trusting what the
/// system trusts. Free it with `storyarc_http_free`.
///
/// # Safety
///
/// `runtime` must be a live runtime handle; `out_http` must point to storage for a pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_http_new(
    runtime: *const c_void,
    out_http: *mut *mut c_void,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { write(out_http, std::ptr::null_mut(), "out_http")? };
        let runtime: &Runtime = unsafe { borrow(runtime, RUNTIME, "runtime")? };
        let http = HttpClient::new(runtime, TrustStore::new()).map_err(|e| http_failure(&e))?;
        // SAFETY: checked writable above.
        unsafe { out_http.write(into_handle(HTTP, http)) };
        Ok(())
    })
}

/// Pins the certificate whose SHA-256 `fingerprint` the reader accepted for `host`, after an
/// `STORYARC_ERROR_UNAUTHORIZED` whose message named it. Both strings are UTF-8 with lengths.
///
/// # Safety
///
/// `http` must be a live HTTP handle; each string must point to its length in readable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_http_pin(
    http: *const c_void,
    host: *const u8,
    host_len: usize,
    fingerprint: *const u8,
    fingerprint_len: usize,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        let http: &HttpClient = unsafe { borrow(http, HTTP, "http")? };
        let host = unsafe { utf8(host, host_len, "host")? };
        let fingerprint = unsafe { utf8(fingerprint, fingerprint_len, "fingerprint")? };
        http.trust().pin(host, fingerprint);
        Ok(())
    })
}

/// Releases the HTTP client. Null is ignored.
///
/// # Safety
///
/// `http` must be null or a live HTTP handle, released once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_http_free(http: *mut c_void) {
    // SAFETY: the caller's promise, passed on.
    unsafe { release::<HttpClient>(http, HTTP) };
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ShareRequest {
    /// `smb://host/share/folder` or `\\host\share\folder`.
    address: String,
    port: Option<u16>,
    username: Option<String>,
    password: Option<String>,
}

/// Connects to a share and writes its handle to `out_share`. The request is
/// `{"address", "port"?, "username"?, "password"?}`; no username is a guest. The four named
/// failures and the SMB 1 refusal come back as status codes with their remedy in the message.
///
/// # Safety
///
/// `runtime` must be a live runtime handle; `request` must point to `request_len` bytes;
/// `out_share` must point to storage for one pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_smb_connect(
    runtime: *const c_void,
    request: *const u8,
    request_len: usize,
    out_share: *mut *mut c_void,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { write(out_share, std::ptr::null_mut(), "out_share")? };
        let runtime: &Runtime = unsafe { borrow(runtime, RUNTIME, "runtime")? };
        let request: ShareRequest = unsafe { json_arg(request, request_len, "request")? };
        let mut address = SmbAddress::parse(&request.address)
            .ok_or_else(|| invalid("the share address is not one"))?;
        if let Some(port) = request.port {
            address = address.with_port(port);
        }
        let login = match request.username.filter(|u| !u.is_empty()) {
            Some(user) => {
                SmbLogin::account(user, Secret::from(request.password.unwrap_or_default()))
            }
            None => SmbLogin::Guest,
        };
        let share = SmbShare::connect(runtime, address, login).map_err(|e| smb_failure(&e))?;
        // SAFETY: checked writable above.
        unsafe { out_share.write(into_handle(SHARE, share)) };
        Ok(())
    })
}

/// Writes `{"dialect", "isEncrypted"}` for a connected share.
///
/// # Safety
///
/// `share` must be a live share handle; `out` must point to one writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_smb_identity(
    share: *const c_void,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let share: &SmbShare = unsafe { borrow(share, SHARE, "share")? };
        let identity = share.identity();
        unsafe {
            write_json(
                out,
                &json!({ "dialect": identity.dialect, "isEncrypted": identity.is_encrypted }),
            )
        }
    })
}

/// Lists one folder of the share, `path` relative to the address's folder (empty for it),
/// as `[{"name", "path", "isDirectory", "length"}]`, folders first, in natural order.
///
/// # Safety
///
/// `share` must be a live share handle; `path` must point to `path_len` bytes; `out` must
/// point to one writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_smb_list(
    share: *const c_void,
    path: *const u8,
    path_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let share: &SmbShare = unsafe { borrow(share, SHARE, "share")? };
        let path = unsafe { utf8(path, path_len, "path")? };
        let entries = share.list(path).map_err(|e| smb_failure(&e))?;
        let listed: Vec<_> = entries
            .iter()
            .map(|e| json!({"name": e.name, "path": e.path, "isDirectory": e.is_directory, "length": e.length}))
            .collect();
        unsafe { write_json(out, &listed) }
    })
}

/// Releases a share and its session. Null is ignored.
///
/// # Safety
///
/// `share` must be null or a live share handle, released once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_smb_free(share: *mut c_void) {
    // SAFETY: the caller's promise, passed on.
    unsafe { release::<SmbShare>(share, SHARE) };
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CatalogueRequest {
    root: String,
    /// The page to fetch; the root when absent.
    url: Option<String>,
    /// Search terms against the page at `url`.
    search: Option<String>,
    username: Option<String>,
    password: Option<String>,
    token: Option<String>,
}

fn credential(
    username: Option<String>,
    password: Option<String>,
    token: Option<String>,
) -> Option<Credential> {
    match (username, token) {
        (_, Some(token)) => Some(Credential::Bearer(Secret::from(token))),
        (Some(username), None) => Some(Credential::Basic {
            username,
            password: Secret::from(password.unwrap_or_default()),
        }),
        (None, None) => None,
    }
}

fn url(text: &str) -> Result<Url, i32> {
    Url::parse(text).map_err(|_| invalid(&format!("{text} is not an address")))
}

/// Fetches a catalogue page: the root, `url`, or a search of `url` for `search`. The request
/// is `{"root", "url"?, "search"?, "username"?, "password"?, "token"?}`; the credential goes to
/// the root's origin only. Writes the page as JSON, or `{"localOnly": true}` for a catalogue
/// without search. A 401 is `STORYARC_ERROR_UNAUTHORIZED` naming the scheme; an untrusted
/// certificate is the same code naming its fingerprint for `storyarc_http_pin`.
///
/// # Safety
///
/// `http` must be a live HTTP handle; `request` must point to `request_len` bytes; `out` must
/// point to one writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_opds_feed(
    http: *const c_void,
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let http: &HttpClient = unsafe { borrow(http, HTTP, "http")? };
        let request: CatalogueRequest = unsafe { json_arg(request, request_len, "request")? };
        let root = url(&request.root)?;
        let catalogue = OpdsCatalogue::new(
            http,
            root.clone(),
            credential(request.username, request.password, request.token),
        )
        .map_err(|e| opds_failure(&e))?;
        let page = url(request.url.as_deref().unwrap_or(root.as_str()))?;
        let feed = catalogue.feed(&page).map_err(|e| opds_failure(&e))?;
        let value = match request.search {
            Some(terms) => match catalogue
                .search(&feed, &terms)
                .map_err(|e| opds_failure(&e))?
            {
                SearchOutcome::Server(found) => records::feed(&found),
                SearchOutcome::LocalOnly => json!({ "localOnly": true }),
            },
            None => records::feed(&feed),
        };
        unsafe { write_json(out, &value) }
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", tag = "call")]
enum KavitaCall {
    Connect,
    Libraries,
    Series { library: Option<i64> },
    Volumes { series: i64 },
    ContinuePoint { series: i64 },
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct KavitaRequest {
    address: String,
    api_key: String,
    #[serde(flatten)]
    call: KavitaCall,
}

/// One Kavita call: `{"address", "apiKey", "call": "connect" | "libraries" | "series" |
/// "volumes" | "continuePoint", "library"? , "series"?}`. Writes the server's records as
/// JSON with `pages` and `pagesRead` per chapter. A refused key is
/// `STORYARC_ERROR_UNAUTHORIZED`.
///
/// # Safety
///
/// `http` must be a live HTTP handle; `request` must point to `request_len` bytes; `out` must
/// point to one writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_kavita_call(
    http: *const c_void,
    request: *const u8,
    request_len: usize,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let http: &HttpClient = unsafe { borrow(http, HTTP, "http")? };
        let request: KavitaRequest = unsafe { json_arg(request, request_len, "request")? };
        let address = KavitaAddress::parse(&request.address, Secret::from(request.api_key))
            .ok_or_else(|| invalid("the server address is not one"))?;
        let client = KavitaClient::new(http, address).map_err(|e| kavita_failure(&e))?;
        let fail = |e| kavita_failure(&e);
        let value = match request.call {
            KavitaCall::Connect => serde_json::to_value(
                json!({ "username": client.connect().map_err(fail)?.username }),
            ),
            KavitaCall::Libraries => serde_json::to_value(client.libraries().map_err(fail)?),
            KavitaCall::Series { library } => {
                serde_json::to_value(client.series(library).map_err(fail)?)
            }
            KavitaCall::Volumes { series } => {
                serde_json::to_value(client.volumes(series).map_err(fail)?)
            }
            KavitaCall::ContinuePoint { series } => {
                serde_json::to_value(client.continue_point(series).map_err(fail)?)
            }
        }
        .unwrap_or_default();
        unsafe { write_json(out, &value) }
    })
}

/// Writes the connection's state to `out_state`: 0 unmetered (or undescribed), 1 metered,
/// 2 no connection. Polled by the app; a change feeds the download queue's hold.
///
/// # Safety
///
/// `runtime` must be a live runtime handle; `out_state` must point to one writable `int32_t`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_network_state(
    runtime: *const c_void,
    out_state: *mut i32,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { write(out_state, 0, "out_state")? };
        let runtime: &Runtime = unsafe { borrow(runtime, RUNTIME, "runtime")? };
        let state = match metered::system_provider(runtime).network() {
            NetworkState::Unmetered => 0,
            NetworkState::Metered => 1,
            NetworkState::Offline => 2,
        };
        unsafe { write(out_state, state, "out_state") }
    })
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DownloadRequest {
    folder: String,
    id: String,
    title: String,
    url: String,
    series_hint: Option<String>,
    /// The source's root, which alone receives the credential.
    origin: Option<String>,
    username: Option<String>,
    password: Option<String>,
    token: Option<String>,
}

/// Downloads one publication into the downloads folder, resuming a partial file with a range
/// request, verifying it by indexing and moving it into place. The request is `{"folder",
/// "id", "title", "url", "seriesHint"?, "origin"?, "username"?, "password"?, "token"?}`.
/// Writes `{"path", "resumption", "length", "publication"}`. A file that is not a publication
/// is `STORYARC_ERROR_UNREADABLE` (re-queue once); a raised `cancel` keeps the partial file.
///
/// # Safety
///
/// `http` must be a live HTTP handle; `request` must point to `request_len` bytes; `cancel`
/// must be null or a live token; `progress` may be null, and is called on the calling thread
/// with `context`, the bytes so far and the total or -1 when the server named none; `out` must point to one writable `StoryArcBuffer`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn storyarc_download_fetch(
    http: *const c_void,
    request: *const u8,
    request_len: usize,
    cancel: *const c_void,
    progress: Option<unsafe extern "C" fn(*mut c_void, u64, i64)>,
    context: *mut c_void,
    out: *mut StoryArcBuffer,
) -> i32 {
    guard(|| {
        // SAFETY: the caller's promises, passed on.
        unsafe { clear(out)? };
        let http: &HttpClient = unsafe { borrow(http, HTTP, "http")? };
        let request: DownloadRequest = unsafe { json_arg(request, request_len, "request")? };
        let cancel = unsafe { token(cancel) };
        let mut get = Request::get(url(&request.url)?);
        if let Some(origin) = &request.origin {
            let origin =
                Origin::of(&url(origin)?).ok_or_else(|| invalid("the origin is not one"))?;
            get = get.signed(
                origin,
                credential(request.username, request.password, request.token),
            );
        }
        let landed = DownloadFolder::new(&request.folder)
            .fetch(
                http,
                &request.id,
                &request.title,
                get,
                request.series_hint.as_deref(),
                &cancel,
                |received, total| {
                    if let Some(report) = progress {
                        let total = total.and_then(|t| i64::try_from(t).ok()).unwrap_or(-1);
                        // SAFETY: the caller's callback and context, on the caller's thread.
                        unsafe { report(context, received, total) };
                    }
                },
            )
            .map_err(|e| landing_failure(&e))?;
        let value = json!({
            "path": landed.path.to_string_lossy(),
            "resumption": landed.resumption,
            "length": landed.length,
            "publication": landed.publication,
        });
        unsafe { write_json(out, &value) }
    })
}
