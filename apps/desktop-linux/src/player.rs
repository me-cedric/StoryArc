//! The one player for everything that speaks (task 4.14; `audio-playback`, One player for
//! everything that speaks; `read-aloud-beyond-the-reader`, The transport outside the
//! reader). An audiobook plays through `audio.rs`; a book's text speaks through
//! `speech.rs` on its own thread; both show in the mini player of `player_ui.rs` and in
//! the desktop's controls through `mpris.rs`. While something plays the app holds the
//! session awake with the suspend flag (`desktop-experience`, Keeping the display awake
//! while reading, Listening) and lets it go when it stops. The listening position goes
//! to the core's progress store as the phones write it.
//!
//! The pure parts, the words for a clock, the order of a folder's parts and the text of a
//! chapter's markup, test on any host.

use std::cell::{Cell, RefCell};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use adw::prelude::*;
use gtk::{gio, glib};
use storyarc_core::domain::{
    self, PublicationIdentity, ReadingPosition, ReadingProgress, Timestamp,
};

use crate::app::Shared;
use crate::audio::{AudioPlayer, PlayState, PlayerEvent, Sink};
use crate::idle::IdleHold;
use crate::mpris::{Command, Mpris, NowPlaying, Shown};
use crate::speech::{Speech, SpeechEvent};
use crate::strings::tr;

/// The skips of `audio-playback`, Skipping: fifteen back, thirty forward.
pub const SKIP_BACK: i64 = -15;
pub const SKIP_FORWARD: i64 = 30;
/// How often the listening position is written while playing.
const WRITE_EVERY: Duration = Duration::from_secs(15);

/// What is playing.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Source {
    /// An audiobook: one file, or a folder's parts in order, and the part playing.
    Audio { parts: Vec<PathBuf>, part: usize },
    /// A book read aloud: its text, sentence by sentence.
    Speech { sentences: Vec<String>, at: usize },
}

/// What the bar and the controls show.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Showing {
    pub title: String,
    pub subtitle: String,
    pub cover: Option<PathBuf>,
    pub state: PlayState,
    pub position: Duration,
    pub duration: Option<Duration>,
    pub can_skip: bool,
    pub can_go_next: bool,
    pub can_go_previous: bool,
}

/// Whether a path may be an audiobook: an audio file, or a folder (which the indexer
/// then calls an audiobook folder or not).
pub fn is_audio_path(path: &Path) -> bool {
    if path.is_dir() {
        return true;
    }
    path.extension().is_some_and(|extension| {
        let extension = extension.to_string_lossy().to_ascii_lowercase();
        matches!(
            extension.as_str(),
            "mp3" | "m4a" | "m4b" | "flac" | "ogg" | "oga" | "opus"
        )
    })
}

/// `m:ss`, or `h:mm:ss` from an hour on.
pub fn clock(duration: Duration) -> String {
    let total = duration.as_secs();
    let (hours, minutes, seconds) = (total / 3600, total % 3600 / 60, total % 60);
    if hours > 0 {
        format!("{hours}:{minutes:02}:{seconds:02}")
    } else {
        format!("{minutes}:{seconds:02}")
    }
}

/// A folder's audio files in part order: by name, with a run of digits compared as a
/// number, so `part10` follows `part2` (`publication-formats`, the folder fixture).
pub fn parts_in_order(files: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = files
        .into_iter()
        .filter(|file| {
            file.extension().is_some_and(|extension| {
                let extension = extension.to_string_lossy().to_ascii_lowercase();
                matches!(
                    extension.as_str(),
                    "mp3" | "m4a" | "m4b" | "flac" | "ogg" | "oga" | "opus" | "wav"
                )
            })
        })
        .collect();
    files.sort_by(|a, b| natural(&name(a), &name(b)));
    files
}

fn name(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().to_lowercase())
        .unwrap_or_default()
}

fn natural(a: &str, b: &str) -> std::cmp::Ordering {
    let (mut a, mut b) = (a.chars().peekable(), b.chars().peekable());
    loop {
        match (a.peek().copied(), b.peek().copied()) {
            (None, None) => return std::cmp::Ordering::Equal,
            (None, Some(_)) => return std::cmp::Ordering::Less,
            (Some(_), None) => return std::cmp::Ordering::Greater,
            (Some(x), Some(y)) if x.is_ascii_digit() && y.is_ascii_digit() => {
                let number = |it: &mut std::iter::Peekable<std::str::Chars<'_>>| {
                    let mut value: u64 = 0;
                    while let Some(d) = it.peek().and_then(|c| c.to_digit(10)) {
                        value = value.saturating_mul(10).saturating_add(u64::from(d));
                        it.next();
                    }
                    value
                };
                let order = number(&mut a).cmp(&number(&mut b));
                if order != std::cmp::Ordering::Equal {
                    return order;
                }
            }
            (Some(x), Some(y)) => {
                if x != y {
                    return x.cmp(&y);
                }
                a.next();
                b.next();
            }
        }
    }
}

/// The spoken text of a chapter's markup: tags gone, the common entities decoded, the
/// white space folded, split at sentence ends.
pub fn sentences_of_markup(markup: &str) -> Vec<String> {
    let mut text = String::with_capacity(markup.len());
    let mut in_tag = false;
    let mut skip_until: Option<&str> = None;
    let lower = markup.to_ascii_lowercase();
    let mut i = 0;
    let bytes = markup.as_bytes();
    while i < bytes.len() {
        if let Some(end) = skip_until {
            match lower[i..].find(end) {
                Some(at) => i += at + end.len(),
                None => break,
            }
            skip_until = None;
            continue;
        }
        let c = markup[i..].chars().next().unwrap_or(' ');
        if in_tag {
            if c == '>' {
                in_tag = false;
            }
        } else if c == '<' {
            in_tag = true;
            for (opening, closing) in [
                ("<script", "</script>"),
                ("<style", "</style>"),
                ("<head", "</head>"),
            ] {
                if lower[i..].starts_with(opening) {
                    skip_until = Some(closing);
                    in_tag = false;
                }
            }
            if lower[i..].starts_with("</p>")
                || lower[i..].starts_with("<br")
                || lower[i..].starts_with("</h")
            {
                text.push('\n');
            }
        } else {
            text.push(c);
        }
        i += c.len_utf8();
    }
    let text = text
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&#39;", "'");
    let mut sentences = Vec::new();
    for block in text.split('\n') {
        let block: String = block.split_whitespace().collect::<Vec<_>>().join(" ");
        if block.is_empty() {
            continue;
        }
        let mut start = 0;
        let chars: Vec<(usize, char)> = block.char_indices().collect();
        for (n, (at, c)) in chars.iter().enumerate() {
            let ends = matches!(c, '.' | '!' | '?')
                && chars
                    .get(n + 1)
                    .is_none_or(|(_, next)| next.is_whitespace());
            if ends {
                let end = at + c.len_utf8();
                let sentence = block[start..end].trim();
                if !sentence.is_empty() {
                    sentences.push(sentence.to_owned());
                }
                start = end;
            }
        }
        let rest = block[start..].trim();
        if !rest.is_empty() {
            sentences.push(rest.to_owned());
        }
    }
    sentences
}

/// What the speech thread is told.
enum SpeechOrder {
    Speak(String),
    Pause,
    Resume,
    Stop,
}

/// What the speech thread tells.
enum SpeechWord {
    Begin,
    End,
    Error(String),
}

struct SpeechLine {
    orders: mpsc::Sender<SpeechOrder>,
    words: mpsc::Receiver<SpeechWord>,
}

/// Whether a speech engine is here, asked once per run (`desktop-experience`, A device
/// with no speech engine: the control is absent, nothing says it failed).
pub fn speech_available() -> bool {
    static AVAILABLE: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *AVAILABLE.get_or_init(|| Speech::connect().is_ok())
}

type Listener = Box<dyn Fn(&Showing)>;

pub struct Player {
    shared: std::rc::Weak<crate::app::App>,
    audio: RefCell<Option<Rc<AudioPlayer>>>,
    speech: RefCell<Option<SpeechLine>>,
    mpris: RefCell<Option<Rc<Mpris>>>,
    source: RefCell<Option<Source>>,
    identity: RefCell<Option<PublicationIdentity>>,
    showing: RefCell<Showing>,
    listeners: RefCell<Vec<Listener>>,
    hold: RefCell<IdleHold>,
    written: Cell<Option<Instant>>,
}

impl Player {
    pub fn new(shared: &Shared) -> Rc<Self> {
        let player = Rc::new(Self {
            shared: Rc::downgrade(shared),
            audio: RefCell::default(),
            speech: RefCell::default(),
            mpris: RefCell::default(),
            source: RefCell::default(),
            identity: RefCell::default(),
            showing: RefCell::default(),
            listeners: RefCell::default(),
            hold: RefCell::default(),
            written: Cell::new(None),
        });
        let weak = Rc::downgrade(&player);
        glib::timeout_add_local(Duration::from_millis(250), move || {
            let Some(player) = weak.upgrade() else {
                return glib::ControlFlow::Break;
            };
            player.tick();
            glib::ControlFlow::Continue
        });
        player
    }

    pub fn connect(&self, listener: impl Fn(&Showing) + 'static) {
        self.listeners.borrow_mut().push(Box::new(listener));
    }

    pub fn showing(&self) -> Showing {
        self.showing.borrow().clone()
    }

    /// Plays an audiobook: a file, or a folder whose parts play in order. Starts from the
    /// listening position the store holds.
    pub fn play_audiobook(
        self: &Rc<Self>,
        record: &domain::Publication,
        path: &Path,
    ) -> Result<(), String> {
        let parts = if path.is_dir() {
            let files = std::fs::read_dir(path)
                .map_err(|error| format!("{}: {error}", path.display()))?
                .filter_map(|entry| entry.ok().map(|entry| entry.path()))
                .collect();
            parts_in_order(files)
        } else {
            vec![path.to_path_buf()]
        };
        if parts.is_empty() {
            return Err(format!("{}: the folder holds no audio", path.display()));
        }
        if let Some(media_type) = record.format.media_type()
            && !path.is_dir()
            && !AudioPlayer::can_decode(media_type)
        {
            return Err(format!(
                "{}: no decoder for {media_type} is installed",
                record.display_title
            ));
        }
        self.stop_quietly();
        let audio = self.audio()?;
        let (part, offset) = self.saved_position(&record.identity, parts.len());
        *self.identity.borrow_mut() = Some(record.identity.clone());
        *self.source.borrow_mut() = Some(Source::Audio {
            parts: parts.clone(),
            part,
        });
        {
            let mut showing = self.showing.borrow_mut();
            *showing = Showing {
                title: record.display_title.clone(),
                subtitle: record.authors.first().cloned().unwrap_or_default(),
                cover: crate::covers::loose_cover(path),
                can_skip: true,
                can_go_next: parts.len() > 1,
                can_go_previous: parts.len() > 1,
                ..Showing::default()
            };
        }
        glib::g_message!(
            crate::session::LOG_DOMAIN,
            "player: {} part {} of {} from {offset:?}",
            record.display_title,
            part + 1,
            parts.len()
        );
        audio.load(&parts[part]);
        if offset > Duration::ZERO {
            audio.seek(offset);
        }
        audio.play();
        self.publish();
        Ok(())
    }

    /// Reads a text aloud, sentence by sentence, as the book's own transport.
    pub fn read_aloud(self: &Rc<Self>, title: &str, sentences: Vec<String>) -> Result<(), String> {
        if sentences.is_empty() {
            return Err(tr(
                "desktop.w4.player.nothingToSay",
                "This page has nothing to read aloud.",
            ));
        }
        self.stop_quietly();
        let line = self.speech_line()?;
        let _ = line.orders.send(SpeechOrder::Speak(sentences[0].clone()));
        *self.speech.borrow_mut() = Some(line);
        *self.identity.borrow_mut() = None;
        *self.source.borrow_mut() = Some(Source::Speech { sentences, at: 0 });
        *self.showing.borrow_mut() = Showing {
            title: title.to_owned(),
            subtitle: tr("desktop.w4.player.readingAloud", "Reading aloud"),
            state: PlayState::Playing,
            can_skip: false,
            can_go_next: true,
            can_go_previous: true,
            ..Showing::default()
        };
        self.publish();
        Ok(())
    }

    pub fn toggle(self: &Rc<Self>) {
        match &*self.source.borrow() {
            Some(Source::Audio { .. }) => {
                if let Some(audio) = self.audio.borrow().as_ref() {
                    audio.toggle();
                }
            }
            Some(Source::Speech { .. }) => {
                let playing = self.showing.borrow().state == PlayState::Playing;
                if let Some(line) = self.speech.borrow().as_ref() {
                    let _ = line.orders.send(if playing {
                        SpeechOrder::Pause
                    } else {
                        SpeechOrder::Resume
                    });
                }
                self.showing.borrow_mut().state = if playing {
                    PlayState::Paused
                } else {
                    PlayState::Playing
                };
                self.publish();
            }
            None => {}
        }
    }

    pub fn skip(&self, seconds: i64) {
        if let Some(audio) = self.audio.borrow().as_ref() {
            audio.skip(seconds);
        }
    }

    pub fn seek(&self, to: Duration) {
        if let Some(audio) = self.audio.borrow().as_ref() {
            audio.seek(to);
        }
    }

    /// The next part or sentence.
    pub fn next(self: &Rc<Self>) {
        self.step(1);
    }

    pub fn previous(self: &Rc<Self>) {
        self.step(-1);
    }

    fn step(self: &Rc<Self>, by: i64) {
        let source = self.source.borrow().clone();
        match source {
            Some(Source::Audio { parts, part }) => {
                let Some(next) = part
                    .checked_add_signed(by as isize)
                    .filter(|p| *p < parts.len())
                else {
                    return;
                };
                *self.source.borrow_mut() = Some(Source::Audio {
                    parts: parts.clone(),
                    part: next,
                });
                if let Some(audio) = self.audio.borrow().as_ref() {
                    audio.load(&parts[next]);
                    audio.play();
                }
                self.publish();
            }
            Some(Source::Speech { sentences, at }) => {
                let Some(next) = at
                    .checked_add_signed(by as isize)
                    .filter(|n| *n < sentences.len())
                else {
                    self.stop();
                    return;
                };
                *self.source.borrow_mut() = Some(Source::Speech {
                    sentences: sentences.clone(),
                    at: next,
                });
                if let Some(line) = self.speech.borrow().as_ref() {
                    let _ = line.orders.send(SpeechOrder::Stop);
                    let _ = line
                        .orders
                        .send(SpeechOrder::Speak(sentences[next].clone()));
                }
                self.showing.borrow_mut().state = PlayState::Playing;
                self.publish();
            }
            None => {}
        }
    }

    /// Stops and leaves the controls (`desktop-experience`, The system overlay).
    pub fn stop(self: &Rc<Self>) {
        self.stop_quietly();
        self.publish();
    }

    fn stop_quietly(&self) {
        self.write_position(true);
        if let Some(audio) = self.audio.borrow().as_ref() {
            audio.stop();
        }
        if let Some(line) = self.speech.borrow_mut().take() {
            let _ = line.orders.send(SpeechOrder::Stop);
        }
        *self.source.borrow_mut() = None;
        *self.identity.borrow_mut() = None;
        self.mpris.borrow_mut().take();
        let mut showing = self.showing.borrow_mut();
        showing.state = PlayState::Stopped;
        showing.position = Duration::ZERO;
    }

    fn audio(self: &Rc<Self>) -> Result<Rc<AudioPlayer>, String> {
        if let Some(audio) = self.audio.borrow().as_ref() {
            return Ok(audio.clone());
        }
        let sink = if std::env::var_os("STORYARC_AUDIO_NULL_SINK").is_some() {
            Sink::Null
        } else {
            Sink::System
        };
        let audio = AudioPlayer::new(sink)?;
        let weak = Rc::downgrade(self);
        audio.connect(move |event| {
            if let Some(player) = weak.upgrade() {
                player.on_audio(event);
            }
        });
        *self.audio.borrow_mut() = Some(audio.clone());
        Ok(audio)
    }

    fn on_audio(self: &Rc<Self>, event: &PlayerEvent) {
        if !matches!(event, PlayerEvent::Position(_)) {
            glib::g_message!(crate::session::LOG_DOMAIN, "player: {event:?}");
        }
        {
            let mut showing = self.showing.borrow_mut();
            match event {
                PlayerEvent::State(state) => showing.state = *state,
                PlayerEvent::Position(position) => showing.position = *position,
                PlayerEvent::Duration(duration) => showing.duration = Some(*duration),
                PlayerEvent::EndOfStream => {}
                PlayerEvent::Error(reason) => {
                    glib::g_warning!(crate::session::LOG_DOMAIN, "player: {reason}");
                    if let Some(shared) = self.shared.upgrade() {
                        shared.toast(reason);
                    }
                    showing.subtitle = reason.clone();
                    showing.state = PlayState::Stopped;
                }
            }
        }
        if let PlayerEvent::EndOfStream = event {
            let more = matches!(&*self.source.borrow(), Some(Source::Audio { parts, part }) if part + 1 < parts.len());
            if more {
                self.next();
                return;
            }
            self.stop();
            return;
        }
        self.publish();
    }

    /// Starts the speech thread: it owns the socket and answers orders.
    fn speech_line(&self) -> Result<SpeechLine, String> {
        let mut speech = Speech::connect()?;
        let (orders, inbox) = mpsc::channel::<SpeechOrder>();
        let (outbox, words) = mpsc::channel::<SpeechWord>();
        std::thread::Builder::new()
            .name("storyarc-speech".to_owned())
            .spawn(move || {
                let mut speaking: Option<u32> = None;
                loop {
                    let order = if speaking.is_some() {
                        match inbox.try_recv() {
                            Ok(order) => Some(order),
                            Err(mpsc::TryRecvError::Disconnected) => break,
                            Err(mpsc::TryRecvError::Empty) => None,
                        }
                    } else {
                        match inbox.recv() {
                            Ok(order) => Some(order),
                            Err(_) => break,
                        }
                    };
                    match order {
                        Some(SpeechOrder::Speak(text)) => match speech.speak(&text) {
                            Ok(id) => speaking = Some(id),
                            Err(reason) => {
                                let _ = outbox.send(SpeechWord::Error(reason));
                            }
                        },
                        Some(SpeechOrder::Pause) => {
                            let _ = speech.pause();
                        }
                        Some(SpeechOrder::Resume) => {
                            let _ = speech.resume();
                        }
                        Some(SpeechOrder::Stop) => {
                            let _ = speech.stop();
                            speaking = None;
                        }
                        None => match speech.next_event() {
                            Some(SpeechEvent::Begin(_)) => {
                                let _ = outbox.send(SpeechWord::Begin);
                            }
                            Some(SpeechEvent::End(_) | SpeechEvent::Cancel(_)) => {
                                speaking = None;
                                let _ = outbox.send(SpeechWord::End);
                            }
                            Some(_) => {}
                            None => {}
                        },
                    }
                }
                let _ = speech.stop();
            })
            .map_err(|error| error.to_string())?;
        Ok(SpeechLine { orders, words })
    }

    /// The clock: speech words, the position write, the controls.
    fn tick(self: &Rc<Self>) {
        let words: Vec<SpeechWord> = self
            .speech
            .borrow()
            .as_ref()
            .map(|line| line.words.try_iter().collect())
            .unwrap_or_default();
        for word in words {
            match word {
                SpeechWord::Begin => {}
                SpeechWord::End => {
                    let at_end = matches!(&*self.source.borrow(), Some(Source::Speech { sentences, at }) if at + 1 >= sentences.len());
                    if at_end {
                        self.stop();
                    } else {
                        self.next();
                    }
                }
                SpeechWord::Error(reason) => {
                    glib::g_warning!(crate::session::LOG_DOMAIN, "read aloud: {reason}");
                    self.stop();
                }
            }
        }
        self.write_position(false);
    }

    fn saved_position(&self, identity: &PublicationIdentity, parts: usize) -> (usize, Duration) {
        let Some(shared) = self.shared.upgrade() else {
            return (0, Duration::ZERO);
        };
        match shared
            .progress_store()
            .read(identity)
            .ok()
            .flatten()
            .map(|record| record.position)
        {
            Some(ReadingPosition::Listening {
                part,
                offset_millis,
                ..
            }) => (
                usize::try_from(part)
                    .unwrap_or(0)
                    .min(parts.saturating_sub(1)),
                Duration::from_millis(u64::try_from(offset_millis).unwrap_or(0)),
            ),
            _ => (0, Duration::ZERO),
        }
    }

    /// Writes the listening position every fifteen seconds while playing, and `now` on a
    /// pause or a stop (`audio-playback`, Where a listening position is written).
    fn write_position(&self, now: bool) {
        let Some(Source::Audio { parts, part }) = self.source.borrow().clone() else {
            return;
        };
        let Some(identity) = self.identity.borrow().clone() else {
            return;
        };
        let showing = self.showing.borrow().clone();
        let due = self
            .written
            .get()
            .is_none_or(|last| last.elapsed() >= WRITE_EVERY);
        if !(now || (showing.state == PlayState::Playing && due)) {
            return;
        }
        let Some(shared) = self.shared.upgrade() else {
            return;
        };
        let position = ReadingPosition::Listening {
            part: part as i64,
            part_count: parts.len() as i64,
            offset_millis: showing.position.as_millis() as i64,
            of_millis: showing.duration.map(|d| d.as_millis() as i64),
        };
        let record = ReadingProgress::new(identity, position, Timestamp::now());
        if let Err(error) = shared.progress_store().write(&record) {
            glib::g_warning!(crate::session::LOG_DOMAIN, "{error}");
        }
        self.written.set(Some(Instant::now()));
        shared.progress_changed();
    }

    /// Tells the bar, the controls and the session what is showing now.
    fn publish(self: &Rc<Self>) {
        let showing = self.showing.borrow().clone();
        for listener in self.listeners.borrow().iter() {
            listener(&showing);
        }
        if let Some(shared) = self.shared.upgrade() {
            let app = shared.application();
            // The library window carries the inhibit: GTK's Wayland path needs a surface.
            let window = shared.library.borrow().clone();
            if showing.state == PlayState::Playing {
                self.hold.borrow_mut().hold(|| {
                    app.inhibit(
                        window.as_ref(),
                        gtk::ApplicationInhibitFlags::SUSPEND | gtk::ApplicationInhibitFlags::IDLE,
                        Some("Playing"),
                    )
                });
            } else {
                self.hold
                    .borrow_mut()
                    .release(|cookie| app.uninhibit(cookie));
            }
        }
        self.show_in_controls(&showing);
    }

    fn show_in_controls(self: &Rc<Self>, showing: &Showing) {
        if showing.state == PlayState::Stopped && self.source.borrow().is_none() {
            return;
        }
        if self.mpris.borrow().is_none() {
            let Some(connection) =
                gio::bus_get_sync(gio::BusType::Session, None::<&gio::Cancellable>).ok()
            else {
                return;
            };
            let weak = Rc::downgrade(self);
            match Mpris::publish(connection, move |command| {
                if let Some(player) = weak.upgrade() {
                    player.on_command(command);
                }
            }) {
                Ok(mpris) => {
                    glib::g_message!(crate::session::LOG_DOMAIN, "mpris: published");
                    *self.mpris.borrow_mut() = Some(mpris);
                }
                Err(reason) => {
                    glib::g_warning!(crate::session::LOG_DOMAIN, "mpris: {reason}");
                    return;
                }
            }
        }
        let track = match &*self.source.borrow() {
            Some(Source::Audio { part, .. }) => *part as u64,
            Some(Source::Speech { at, .. }) => *at as u64,
            None => 0,
        };
        let shown = Shown {
            status: showing.state,
            position: showing.position,
            rate: self
                .audio
                .borrow()
                .as_ref()
                .map_or(1.0, |audio| audio.rate()),
            now: NowPlaying {
                title: showing.title.clone(),
                author: Some(showing.subtitle.clone()).filter(|s| !s.is_empty()),
                cover: showing.cover.clone(),
                length: showing.duration,
                track,
            },
            can_go_next: showing.can_go_next,
            can_go_previous: showing.can_go_previous,
        };
        if let Some(mpris) = self.mpris.borrow().as_ref() {
            mpris.show(shown, false);
        }
    }

    fn on_command(self: &Rc<Self>, command: Command) {
        match command {
            Command::PlayPause => self.toggle(),
            Command::Play if self.showing.borrow().state != PlayState::Playing => self.toggle(),
            Command::Pause if self.showing.borrow().state == PlayState::Playing => self.toggle(),
            Command::Play | Command::Pause => {}
            Command::Stop => self.stop(),
            Command::Next => self.next(),
            Command::Previous => self.previous(),
            Command::Seek(micros) => self.skip(micros / 1_000_000),
            Command::SetPosition(to) => self.seek(to),
            Command::SetRate(rate) => {
                if let Some(audio) = self.audio.borrow().as_ref() {
                    audio.set_rate(rate);
                }
            }
            Command::Raise => {
                if let Some(window) = self
                    .shared
                    .upgrade()
                    .and_then(|shared| shared.library.borrow().clone())
                {
                    window.present();
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_clock_reads_minutes_and_hours() {
        assert_eq!(clock(Duration::from_secs(5)), "0:05");
        assert_eq!(clock(Duration::from_secs(754)), "12:34");
        assert_eq!(clock(Duration::from_secs(3600 + 62)), "1:01:02");
    }

    #[test]
    fn parts_sort_naturally_and_only_audio_counts() {
        let files: Vec<PathBuf> = [
            "part10.mp3",
            "cover.png",
            "part2.mp3",
            "Part1.mp3",
            "notes.txt",
        ]
        .iter()
        .map(|n| PathBuf::from(format!("/book/{n}")))
        .collect();
        let names: Vec<String> = parts_in_order(files).iter().map(|p| name(p)).collect();
        assert_eq!(names, ["part1.mp3", "part2.mp3", "part10.mp3"]);
    }

    #[test]
    fn markup_becomes_sentences_without_tags_scripts_or_entities() {
        let markup = r#"<html><head><title>Skip</title><style>p{}</style></head><body>
<h1>Chapter One</h1><p>It was late. The <em>lamp</em> flickered &amp; died!</p>
<script>alert(1)</script><p>Was anyone there?<br/>No one.</p></body></html>"#;
        assert_eq!(
            sentences_of_markup(markup),
            [
                "Chapter One",
                "It was late.",
                "The lamp flickered & died!",
                "Was anyone there?",
                "No one."
            ]
        );
        assert!(sentences_of_markup("<p>   </p>").is_empty());
    }
}
