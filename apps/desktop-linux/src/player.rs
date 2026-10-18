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
use crate::playback::{self, Chapter, Countdown, SleepTimer, Speeds};
use crate::strings::{tr, tr_args};
/// How often the listening position is written while playing.
const WRITE_EVERY: Duration = Duration::from_secs(15);
/// How long a scrub rests before its position is written: once the listener lets go.
const SCRUB_REST: Duration = Duration::from_millis(600);

/// A chapter a voice reads: its resource, its name and its sentences.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SpokenChapter {
    pub href: String,
    pub title: String,
    pub sentences: Vec<String>,
}

/// A book handed to the voice: what it is called, where it lives, its chapters and the one
/// to start at.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoiceBook {
    pub title: String,
    pub path: PathBuf,
    /// The key its speed is remembered under, and its series.
    pub key: String,
    pub series: Option<String>,
    pub chapters: Vec<SpokenChapter>,
    pub part: usize,
}

/// What is playing.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Source {
    /// An audiobook: one file, or a folder's parts in order, and the part playing.
    Audio { parts: Vec<PathBuf>, part: usize },
    /// A book read aloud, chapter by chapter and sentence by sentence.
    Speech {
        chapters: Vec<SpokenChapter>,
        part: usize,
        at: usize,
    },
}

/// What the bar, the full player and the controls show. One source feeds every surface.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Showing {
    pub title: String,
    /// The second line: the chapter being heard, else the author.
    pub subtitle: String,
    pub cover: Option<PathBuf>,
    pub state: PlayState,
    pub position: Duration,
    pub duration: Option<Duration>,
    pub can_skip: bool,
    pub can_go_next: bool,
    pub can_go_previous: bool,
    /// The book's own file, the way back to where the audio reads.
    pub book: Option<PathBuf>,
    /// A voice reads it, rather than a narrator.
    pub voice: bool,
    /// The format's name, for the coverless artwork.
    pub format: String,
    /// The chapter list: a file's chapters, a folder's parts or the chapters a voice reads.
    pub chapters: Vec<Chapter>,
    pub chapter: Option<usize>,
    pub part: usize,
    /// The resource and the sentence the voice is on, for the page to draw and follow.
    pub spoken: Option<(String, String)>,
    pub speed: f64,
    pub sleep: Option<Countdown>,
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
    Rate(i32),
    Volume(i32),
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

/// The voice that reads, named once on a book's own page rather than in the player
/// (`audio-playback`, *Both sources look the same*). Asked once per run.
pub fn voice_name() -> Option<String> {
    static NAME: std::sync::OnceLock<Option<String>> = std::sync::OnceLock::new();
    NAME.get_or_init(|| Speech::connect().ok()?.output_module().ok())
        .clone()
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
    /// The parts' lengths, as far as they are known.
    lengths: RefCell<Vec<Option<Duration>>>,
    /// The book's key and series, for the speed it remembers.
    key: RefCell<Option<(String, Option<String>)>>,
    speeds: RefCell<Speeds>,
    last_tick: Cell<Option<Instant>>,
    scrub: RefCell<Option<glib::SourceId>>,
    /// The audio outputs, watched so a lost one pauses the book.
    outputs: RefCell<Option<(gstreamer::DeviceMonitor, gstreamer::bus::BusWatchGuard)>>,
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
            showing: RefCell::new(Showing {
                speed: 1.0,
                ..Showing::default()
            }),
            listeners: RefCell::default(),
            hold: RefCell::default(),
            written: Cell::new(None),
            lengths: RefCell::default(),
            key: RefCell::default(),
            speeds: RefCell::new(crate::session::load_speeds()),
            last_tick: Cell::new(None),
            scrub: RefCell::default(),
            outputs: RefCell::default(),
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

    /// The book a voice is reading now, if one is.
    pub fn voice_book(&self) -> Option<PathBuf> {
        let showing = self.showing.borrow();
        (showing.voice && showing.state != PlayState::Stopped)
            .then(|| showing.book.clone())
            .flatten()
    }

    /// Plays an audiobook: a file, or a folder whose parts play in order. Starts from the
    /// listening position the store holds, or at `from` (a part and an offset), which leaves
    /// the stored position as it was until the listener moves.
    pub fn play_audiobook(
        self: &Rc<Self>,
        record: &domain::Publication,
        path: &Path,
        from: Option<(usize, Duration)>,
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
        let (part, offset) =
            from.unwrap_or_else(|| self.saved_position(&record.identity, parts.len()));
        let part = part.min(parts.len() - 1);
        *self.identity.borrow_mut() = Some(record.identity.clone());
        *self.source.borrow_mut() = Some(Source::Audio {
            parts: parts.clone(),
            part,
        });
        let key = speed_key(&record.identity, path);
        let speed = self.speeds.borrow().speed(&key, record.series.as_deref());
        *self.key.borrow_mut() = Some((key, record.series.clone()));
        *self.lengths.borrow_mut() = vec![None; parts.len()];
        {
            let mut showing = self.showing.borrow_mut();
            *showing = Showing {
                title: record.display_title.clone(),
                subtitle: record.authors.first().cloned().unwrap_or_default(),
                cover: crate::covers::loose_cover(path),
                can_skip: true,
                can_go_next: parts.len() > 1,
                can_go_previous: parts.len() > 1,
                book: Some(path.to_path_buf()),
                format: record.format.display_name().to_owned(),
                chapters: parts_as_chapters(&parts),
                part,
                speed,
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
        audio.set_rate(speed);
        if offset > Duration::ZERO {
            audio.seek(offset);
        }
        audio.play();
        self.publish();
        self.read_chapters(parts);
        Ok(())
    }

    /// Reads every part's chapters and length on a worker, then lists them.
    fn read_chapters(self: &Rc<Self>, parts: Vec<PathBuf>) {
        let weak = Rc::downgrade(self);
        glib::spawn_future_local(async move {
            let read = gio::spawn_blocking(move || {
                let (chapters, lengths) = book_chapters(&parts);
                (parts, chapters, lengths)
            })
            .await;
            let (Some(player), Ok((parts, chapters, lengths))) = (weak.upgrade(), read) else {
                return;
            };
            // A later book may have replaced this one while the worker read.
            let same = matches!(&*player.source.borrow(), Some(Source::Audio { parts: now, .. }) if *now == parts);
            if !same {
                return;
            }
            *player.lengths.borrow_mut() = lengths;
            player.showing.borrow_mut().chapters = chapters;
            player.follow_chapter();
            player.publish();
        });
    }

    /// Reads a book aloud, from the start of `book.part`, as the book's own transport.
    pub fn read_aloud(self: &Rc<Self>, book: VoiceBook) -> Result<(), String> {
        let part = book.part.min(book.chapters.len().saturating_sub(1));
        let Some(at) = book
            .chapters
            .iter()
            .skip(part)
            .position(|chapter| !chapter.sentences.is_empty())
            .map(|offset| part + offset)
        else {
            return Err(tr(
                "desktop.w4.player.nothingToSay",
                "This page has nothing to read aloud.",
            ));
        };
        self.stop_quietly();
        let line = self.speech_line()?;
        let speed = self.speeds.borrow().speed(&book.key, book.series.as_deref());
        let _ = line.orders.send(SpeechOrder::Rate(speech_rate(speed)));
        *self.speech.borrow_mut() = Some(line);
        *self.identity.borrow_mut() = None;
        *self.key.borrow_mut() = Some((book.key.clone(), book.series.clone()));
        let chapters = book
            .chapters
            .iter()
            .enumerate()
            .map(|(part, chapter)| Chapter {
                title: Some(chapter.title.clone()).filter(|t| !t.is_empty()),
                part,
                ..Chapter::default()
            })
            .collect();
        *self.showing.borrow_mut() = Showing {
            title: book.title.clone(),
            state: PlayState::Playing,
            can_skip: true,
            can_go_next: true,
            can_go_previous: true,
            book: Some(book.path.clone()),
            voice: true,
            format: "EPUB".to_owned(),
            chapters,
            speed,
            ..Showing::default()
        };
        *self.source.borrow_mut() = Some(Source::Speech {
            chapters: book.chapters,
            part: at,
            at: 0,
        });
        self.speak_current();
        Ok(())
    }

    /// Speaks the sentence the source is on and tells every surface which it is.
    fn speak_current(self: &Rc<Self>) {
        let current = match &*self.source.borrow() {
            Some(Source::Speech { chapters, part, at }) => chapters.get(*part).and_then(|chapter| {
                Some((*part, chapter.href.clone(), chapter.title.clone(), chapter.sentences.get(*at)?.clone()))
            }),
            _ => None,
        };
        let Some((part, href, title, sentence)) = current else {
            return;
        };
        if let Some(line) = self.speech.borrow().as_ref() {
            let _ = line.orders.send(SpeechOrder::Stop);
            let _ = line.orders.send(SpeechOrder::Speak(sentence.clone()));
        }
        {
            let mut showing = self.showing.borrow_mut();
            showing.state = PlayState::Playing;
            showing.part = part;
            showing.chapter = Some(part);
            showing.subtitle = title;
            showing.spoken = Some((href, sentence));
        }
        self.publish();
    }

    pub fn toggle(self: &Rc<Self>) {
        let source = self.source.borrow().clone();
        match source {
            Some(Source::Audio { .. }) => {
                let audio = self.audio.borrow().clone();
                if let Some(audio) = audio {
                    let playing = self.showing.borrow().state == PlayState::Playing;
                    audio.toggle();
                    if playing {
                        self.write_position(true);
                    }
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

    /// Fifteen seconds back or thirty forward, into the neighbouring part at a boundary; for
    /// a voice, a sentence (`audio-playback`, *Skipping*; `ebook-reader`, sentence skip).
    pub fn skip_by(self: &Rc<Self>, forward: bool) {
        let source = self.source.borrow().clone();
        match source {
            Some(Source::Audio { parts, part }) => {
                let Some(audio) = self.audio.borrow().clone() else {
                    return;
                };
                let offset = audio.position().unwrap_or_default();
                let mut lengths = self.lengths.borrow().clone();
                if let Some(length) = audio.duration() {
                    lengths.resize(parts.len(), None);
                    lengths[part] = Some(length);
                }
                let (to_part, to) = playback::skip(&lengths, part, offset, forward);
                if to_part != part {
                    self.load_part(&parts, to_part);
                }
                audio.seek(to);
                self.showing.borrow_mut().position = to;
                self.write_at(to_part, to);
            }
            Some(Source::Speech { .. }) => self.step(if forward { 1 } else { -1 }),
            None => {}
        }
    }

    /// A move by seconds from the desktop's controls; a voice moves by a sentence.
    fn skip_seconds(self: &Rc<Self>, seconds: i64) {
        if self.showing.borrow().voice {
            self.step(seconds.signum());
            return;
        }
        if let Some(audio) = self.audio.borrow().as_ref() {
            audio.skip(seconds);
        }
        self.write_position(true);
    }

    /// A scrub. The position is written once the slider rests, not at every step of a drag.
    pub fn seek(self: &Rc<Self>, to: Duration) {
        if let Some(audio) = self.audio.borrow().as_ref() {
            audio.seek(to);
        }
        if let Some(source) = self.scrub.borrow_mut().take() {
            source.remove();
        }
        let weak = Rc::downgrade(self);
        let source = glib::timeout_add_local_once(SCRUB_REST, move || {
            if let Some(player) = weak.upgrade() {
                player.scrub.borrow_mut().take();
                player.write_position(true);
            }
        });
        *self.scrub.borrow_mut() = Some(source);
    }

    /// Goes to a stop of the chapter list (`audio-playback`, *Chapters*).
    pub fn play_chapter(self: &Rc<Self>, index: usize) {
        let Some(chapter) = self.showing.borrow().chapters.get(index).cloned() else {
            return;
        };
        let source = self.source.borrow().clone();
        match source {
            Some(Source::Audio { parts, part }) => {
                if chapter.part != part {
                    self.load_part(&parts, chapter.part);
                }
                if let Some(audio) = self.audio.borrow().as_ref() {
                    audio.seek(chapter.start);
                    audio.play();
                }
                self.showing.borrow_mut().position = chapter.start;
                self.write_at(chapter.part, chapter.start);
                self.follow_chapter();
                self.publish();
            }
            Some(Source::Speech { chapters, .. }) => {
                *self.source.borrow_mut() = Some(Source::Speech {
                    chapters,
                    part: chapter.part,
                    at: 0,
                });
                self.speak_current();
            }
            None => {}
        }
    }

    fn load_part(self: &Rc<Self>, parts: &[PathBuf], part: usize) {
        *self.source.borrow_mut() = Some(Source::Audio {
            parts: parts.to_vec(),
            part,
        });
        self.showing.borrow_mut().part = part;
        if let Some(audio) = self.audio.borrow().as_ref() {
            audio.load(&parts[part]);
            audio.set_rate(self.showing.borrow().speed);
            audio.play();
        }
    }

    /// The speed, half to triple, remembered for the book and its series (`audio-playback`,
    /// *Speed*).
    pub fn set_speed(self: &Rc<Self>, rate: f64) {
        let rate = playback::clamp_speed(rate);
        if let Some(audio) = self.audio.borrow().as_ref() {
            audio.set_rate(rate);
        }
        if let Some(line) = self.speech.borrow().as_ref() {
            let _ = line.orders.send(SpeechOrder::Rate(speech_rate(rate)));
        }
        if let Some((key, series)) = self.key.borrow().clone() {
            self.speeds.borrow_mut().remember(&key, series.as_deref(), rate);
            crate::session::save_speeds(&self.speeds.borrow());
        }
        self.showing.borrow_mut().speed = rate;
        self.publish();
    }

    /// Sets or clears the sleep timer (`audio-playback`, *Sleep timer*). A voice has no clock
    /// for its chapter, so its end of chapter waits for the chapter's last sentence.
    pub fn set_sleep(self: &Rc<Self>, timer: Option<SleepTimer>) {
        let voice = self.showing.borrow().voice;
        let countdown = timer.and_then(|timer| match (timer, voice) {
            (SleepTimer::EndOfChapter, true) => Some(Countdown {
                timer,
                remaining: Duration::MAX,
            }),
            _ => Countdown::of(timer, self.left_in_chapter()),
        });
        self.showing.borrow_mut().sleep = countdown;
        if countdown.is_none()
            && let Some(audio) = self.audio.borrow().as_ref()
        {
            audio.set_volume(1.0);
        }
        self.publish();
    }

    /// Whether *End of chapter* can be offered: a voice knows its chapters, a narrated book
    /// needs a chapter or a part with a length.
    pub fn can_sleep_at_end_of_chapter(&self) -> bool {
        self.showing.borrow().voice || self.left_in_chapter().is_some()
    }

    /// What is left of the chapter the narrator is in, when its length is known.
    fn left_in_chapter(&self) -> Option<Duration> {
        let showing = self.showing.borrow();
        let position = self
            .audio
            .borrow()
            .as_ref()
            .and_then(|audio| audio.position())
            .unwrap_or(showing.position);
        let end = showing
            .chapter
            .and_then(|index| showing.chapters.get(index))
            .and_then(|chapter| chapter.end)
            .or(showing.duration)?;
        Some(end.saturating_sub(position))
    }

    /// The chapter the narrator is inside now, on the second line.
    fn follow_chapter(&self) {
        let mut showing = self.showing.borrow_mut();
        if showing.voice {
            return;
        }
        let at = playback::chapter_at(&showing.chapters, showing.part, showing.position);
        if at != showing.chapter {
            showing.chapter = at;
            if let Some(chapter) = at.and_then(|index| showing.chapters.get(index)).cloned()
                && (chapter.title.is_some() || showing.chapters.len() > 1)
            {
                showing.subtitle = playback::chapter_name(&chapter, at.unwrap_or(0));
            }
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
                self.load_part(&parts, next);
                self.showing.borrow_mut().position = Duration::ZERO;
                self.write_at(next, Duration::ZERO);
                self.follow_chapter();
                self.publish();
            }
            Some(Source::Speech { chapters, part, at }) => {
                let place = if by >= 0 {
                    let last = chapters.get(part).map_or(0, |c| c.sentences.len());
                    if at + 1 < last {
                        Some((part, at + 1))
                    } else {
                        // The end of a chapter: on into the next one that has words, unless
                        // the sleep timer waits for exactly this.
                        let sleeps = self
                            .showing
                            .borrow()
                            .sleep
                            .is_some_and(|sleep| sleep.timer == SleepTimer::EndOfChapter);
                        if sleeps {
                            self.showing.borrow_mut().sleep = None;
                            self.pause_voice();
                            return;
                        }
                        (part + 1..chapters.len())
                            .find(|p| !chapters[*p].sentences.is_empty())
                            .map(|p| (p, 0))
                    }
                } else if at > 0 {
                    Some((part, at - 1))
                } else {
                    (0..part)
                        .rev()
                        .find(|p| !chapters[*p].sentences.is_empty())
                        .map(|p| (p, chapters[p].sentences.len() - 1))
                        .or(Some((part, 0)))
                };
                let Some((part, at)) = place else {
                    self.stop();
                    return;
                };
                *self.source.borrow_mut() = Some(Source::Speech { chapters, part, at });
                self.speak_current();
            }
            None => {}
        }
    }

    fn pause_voice(self: &Rc<Self>) {
        if let Some(line) = self.speech.borrow().as_ref() {
            let _ = line.orders.send(SpeechOrder::Pause);
        }
        self.showing.borrow_mut().state = PlayState::Paused;
        self.publish();
    }

    /// Stops and leaves the controls (`desktop-experience`, The system overlay).
    pub fn stop(self: &Rc<Self>) {
        self.stop_quietly();
        self.publish();
    }

    /// `ebook-reader`, *Opening a different publication*: a voice reading another book ends at
    /// its sentence, and the sentence that says so comes back once, for the opening window.
    pub fn displace_voice(self: &Rc<Self>, opening: &Path) -> Option<String> {
        let book = self.voice_book()?;
        if book == opening {
            return None;
        }
        let title = self.showing.borrow().title.clone();
        self.stop();
        Some(tr_args(
            "player.voice.stopped %s",
            "Stopped reading “%s” aloud.",
            &[&title],
        ))
    }

    fn stop_quietly(&self) {
        self.write_position(true);
        if let Some(audio) = self.audio.borrow().as_ref() {
            audio.stop();
            audio.set_volume(1.0);
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
        showing.sleep = None;
        showing.spoken = None;
    }

    fn audio(self: &Rc<Self>) -> Result<Rc<AudioPlayer>, String> {
        if let Some(audio) = self.audio.borrow().as_ref() {
            return Ok(audio.clone());
        }
        let sink = if std::env::var_os("STORYARC_AUDIO_NULL_SINK").is_some() || cfg!(test) {
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
        self.watch_outputs();
        Ok(audio)
    }

    /// `audio-playback`, *Headphones removed*: an audio output that goes away while the book
    /// plays pauses it; one that comes back starts nothing.
    fn watch_outputs(self: &Rc<Self>) {
        use gstreamer::prelude::*;
        let monitor = gstreamer::DeviceMonitor::new();
        monitor.add_filter(Some("Audio/Sink"), None);
        let bus = monitor.bus();
        let weak = Rc::downgrade(self);
        let watch = bus.add_watch_local(move |_, message| {
            let removed = matches!(message.view(), gstreamer::MessageView::DeviceRemoved(_));
            if let Some(player) = weak.upgrade() {
                let playing = player.showing.borrow().state == PlayState::Playing;
                if playback::pauses_when_output_goes(removed, playing) {
                    glib::g_message!(crate::session::LOG_DOMAIN, "player: an output went away");
                    player.toggle();
                }
            }
            glib::ControlFlow::Continue
        });
        match (watch, monitor.start()) {
            (Ok(watch), Ok(())) => *self.outputs.borrow_mut() = Some((monitor, watch)),
            (_, Err(error)) => {
                glib::g_message!(crate::session::LOG_DOMAIN, "player: no device monitor: {error}");
            }
            (Err(error), _) => {
                glib::g_message!(crate::session::LOG_DOMAIN, "player: no device bus: {error}");
            }
        }
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
            let sleeps = self
                .showing
                .borrow()
                .sleep
                .is_some_and(|sleep| sleep.timer == SleepTimer::EndOfChapter);
            if more && !sleeps {
                self.next();
                return;
            }
            self.stop();
            return;
        }
        self.follow_chapter();
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
                        Some(SpeechOrder::Rate(rate)) => {
                            let _ = speech.set_rate(rate);
                        }
                        Some(SpeechOrder::Volume(volume)) => {
                            let _ = speech.set_volume(volume);
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

    /// The clock: speech words, the sleep timer, the position write, the controls.
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
                    if self.showing.borrow().state == PlayState::Playing {
                        self.next();
                    }
                }
                SpeechWord::Error(reason) => {
                    glib::g_warning!(crate::session::LOG_DOMAIN, "read aloud: {reason}");
                    self.stop();
                }
            }
        }
        let now = Instant::now();
        let elapsed = self.last_tick.replace(Some(now)).map(|last| now - last);
        self.tick_sleep(elapsed.unwrap_or_default());
        self.write_position(false);
    }

    fn tick_sleep(self: &Rc<Self>, elapsed: Duration) {
        let Some(sleep) = self.showing.borrow().sleep else {
            return;
        };
        if self.showing.borrow().state != PlayState::Playing {
            return;
        }
        let voice = self.showing.borrow().voice;
        let left = if voice { None } else { self.left_in_chapter() };
        let before = sleep;
        let sleep = sleep.ticked(elapsed, left);
        self.showing.borrow_mut().sleep = Some(sleep);
        if let Some(audio) = self.audio.borrow().as_ref().filter(|_| !voice) {
            audio.set_volume(sleep.gain(playback::FADE));
        }
        if let Some(line) = self.speech.borrow().as_ref().filter(|_| voice) {
            // speech-dispatcher's volume runs -100 to 100 around its default.
            let volume = (sleep.gain(playback::VOICE_FADE) * 200.0 - 100.0).round() as i32;
            let _ = line.orders.send(SpeechOrder::Volume(volume));
        }
        if sleep.has_elapsed() {
            self.showing.borrow_mut().sleep = None;
            if voice {
                self.pause_voice();
                return;
            }
            let audio = self.audio.borrow().clone();
            if let Some(audio) = audio {
                audio.pause();
                audio.set_volume(1.0);
                let part = self.showing.borrow().part;
                let offset = audio.position().unwrap_or_default();
                self.write_at(part, playback::recorded_after_fade(offset));
            }
        }
        // The remaining time on the player moves a second at a time.
        if before.remaining.as_secs() != sleep.remaining.as_secs() {
            self.publish();
        }
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
    /// pause, a skip, a scrub, a chapter, a part or a stop (`audio-playback`, Where a
    /// listening position is written). The position is read from the engine as it writes.
    fn write_position(&self, now: bool) {
        let Some(Source::Audio { part, .. }) = self.source.borrow().clone() else {
            return;
        };
        let playing = self.showing.borrow().state == PlayState::Playing;
        let due = self
            .written
            .get()
            .is_none_or(|last| last.elapsed() >= WRITE_EVERY);
        if !(now || (playing && due)) {
            return;
        }
        let offset = self
            .audio
            .borrow()
            .as_ref()
            .and_then(|audio| audio.position())
            .unwrap_or(self.showing.borrow().position);
        self.write_at(part, offset);
    }

    fn write_at(&self, part: usize, offset: Duration) {
        let Some(Source::Audio { parts, .. }) = self.source.borrow().clone() else {
            return;
        };
        let Some(identity) = self.identity.borrow().clone() else {
            return;
        };
        let Some(shared) = self.shared.upgrade() else {
            return;
        };
        let length = self.lengths.borrow().get(part).copied().flatten().or(self.showing.borrow().duration);
        let position = ReadingPosition::Listening {
            part: part as i64,
            part_count: parts.len() as i64,
            offset_millis: offset.as_millis() as i64,
            of_millis: length.map(|d| d.as_millis() as i64),
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
        if let Some(app) = self.shared.upgrade().and_then(|shared| {
            let app = shared.started_application()?;
            Some((shared, app))
        }) {
            let (shared, app) = app;
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
        // The player's tests leave the session bus to the MPRIS tests, which own their own bus.
        if cfg!(test) {
            return;
        }
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
            Some(Source::Audio { part, .. }) => (*part as u64) << 16 | showing.chapter.unwrap_or(0) as u64,
            Some(Source::Speech { part, at, .. }) => (*part as u64) << 16 | *at as u64,
            None => 0,
        };
        let shown = Shown {
            status: showing.state,
            position: showing.position,
            rate: showing.speed.max(0.5),
            now: NowPlaying {
                title: showing.title.clone(),
                author: Some(showing.subtitle.clone()).filter(|s| !s.is_empty()),
                cover: showing
                    .cover
                    .clone()
                    .or_else(|| coverless_file(!showing.voice, &showing.format)),
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
            Command::Seek(micros) => self.skip_seconds(micros / 1_000_000),
            Command::SetPosition(to) => self.seek(to),
            Command::SetRate(rate) => self.set_speed(rate),
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

/// An audiobook's parts: the file itself, or a folder's audio files in order.
pub fn audiobook_parts(path: &Path) -> Vec<PathBuf> {
    if !path.is_dir() {
        return vec![path.to_path_buf()];
    }
    let files = std::fs::read_dir(path)
        .map(|entries| entries.filter_map(|entry| entry.ok().map(|entry| entry.path())).collect())
        .unwrap_or_default();
    parts_in_order(files)
}

/// The chapter list of a book's parts, and each part's length: a part's own chapters, or the
/// part itself when it has none. Blocks: call it from a worker.
pub fn book_chapters(parts: &[PathBuf]) -> (Vec<Chapter>, Vec<Option<Duration>>) {
    let several = parts.len() > 1;
    let mut chapters = Vec::new();
    let mut lengths = Vec::new();
    for (part, path) in parts.iter().enumerate() {
        let (marks, length) = crate::audio::read_chapters(path).unwrap_or_default();
        lengths.push(length);
        if marks.is_empty() {
            chapters.push(Chapter {
                title: several.then(|| name(path)),
                part,
                start: Duration::ZERO,
                end: length,
            });
        } else {
            chapters.extend(marks.into_iter().map(|mark| Chapter { part, ..mark }));
        }
    }
    (chapters, lengths)
}

/// Where a listener stopped in a book, from the store.
pub fn stopped_at(shared: &Shared, identity: &PublicationIdentity) -> Option<(usize, Duration)> {
    match shared.progress_store().read(identity).ok().flatten()?.position {
        ReadingPosition::Listening { part, offset_millis, .. } => Some((
            usize::try_from(part).unwrap_or(0),
            Duration::from_millis(u64::try_from(offset_millis).unwrap_or(0)),
        )),
        _ => None,
    }
}

/// A folder's parts as a chapter list until their own chapters are read.
fn parts_as_chapters(parts: &[PathBuf]) -> Vec<Chapter> {
    if parts.len() < 2 {
        return Vec::new();
    }
    parts
        .iter()
        .enumerate()
        .map(|(part, path)| Chapter {
            title: Some(name(path)),
            part,
            ..Chapter::default()
        })
        .collect()
}

/// The key a book's speed is remembered under: its content, else its path.
pub fn speed_key(identity: &PublicationIdentity, path: &Path) -> String {
    identity
        .content_digest
        .clone()
        .or_else(|| identity.normalized_path.clone())
        .unwrap_or_else(|| path.to_string_lossy().into_owned())
}

/// speech-dispatcher's rate, -100 to 100 around its own default, for a speed of half to triple.
fn speech_rate(speed: f64) -> i32 {
    (((playback::clamp_speed(speed) - 1.0) * 50.0).round() as i32).clamp(-100, 100)
}

/// The coverless artwork written once to the cache, for the desktop's media controls.
fn coverless_file(audio: bool, format: &str) -> Option<PathBuf> {
    let name: String = format.chars().filter(char::is_ascii_alphanumeric).collect();
    let path = glib::user_cache_dir()
        .join(crate::APP_ID)
        .join(format!("coverless-{}-{name}.svg", if audio { "audio" } else { "text" }));
    if !path.is_file() {
        std::fs::create_dir_all(path.parent()?).ok()?;
        std::fs::write(&path, playback::coverless_svg(audio, format)).ok()?;
    }
    Some(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../packages/test-fixtures/audiobooks")
            .join(name)
    }

    fn pump_until(seconds: f64, mut done: impl FnMut() -> bool) -> bool {
        let context = glib::MainContext::thread_default().unwrap_or_default();
        let end = Instant::now() + Duration::from_secs_f64(seconds);
        while Instant::now() < end {
            context.iteration(false);
            if done() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        done()
    }

    fn listened(shared: &Shared, identity: &PublicationIdentity) -> Option<(i64, i64)> {
        match shared.progress_store().read(identity).ok().flatten()?.position {
            ReadingPosition::Listening { part, offset_millis, .. } => Some((part, offset_millis)),
            _ => None,
        }
    }

    /// `audio-playback`, *Chapters*, *Where a listening position is written*, *Skipping* and
    /// *Sleep timer*, on the one player over the corpus M4B on a silent sink: its chapters are
    /// listed and named on the second line, a chapter chosen and a pause are written at once,
    /// a skip back moves fifteen seconds and is written, and the timer starts and clears.
    #[test]
    fn a_narrated_book_lists_its_chapters_and_writes_each_move() {
        let context = glib::MainContext::new();
        context
            .with_thread_default(narrated_book)
            .expect("the context is this thread's");
    }

    fn narrated_book() {
        if !AudioPlayer::can_decode("audio/mp4") {
            eprintln!("skipped: no MP4 demuxer");
            return;
        }
        let shared = crate::app::App::for_tests();
        let player = Player::new(&shared);
        let path = fixture("chaptered.m4b");
        let record = storyarc_core::sources::PublicationIndexer::index_path(&path, None).expect("the fixture");
        // *Starting from a chapter*: the book starts there, and nothing is written by looking.
        player
            .play_audiobook(&record, &path, Some((0, Duration::from_millis(2100))))
            .expect("it plays");
        assert!(
            pump_until(10.0, || player.showing().chapters.len() >= 2
                && player.showing().chapter == Some(1)),
            "{:?}",
            player.showing()
        );
        assert_eq!(listened(&shared, &record.identity), None);
        let showing = player.showing();
        assert_eq!(showing.subtitle, playback::chapter_name(&showing.chapters[1], 1));
        assert!(showing.book.as_deref() == Some(path.as_path()) && !showing.voice);
        assert_eq!(showing.format, record.format.display_name());

        let second = showing.chapters[1].start;
        player.play_chapter(1);
        let written = listened(&shared, &record.identity).expect("a chapter is written");
        assert_eq!(written, (0, second.as_millis() as i64));
        assert!(pump_until(3.0, || player.showing().chapter == Some(1)));

        pump_until(0.5, || false);
        player.toggle();
        assert!(pump_until(3.0, || player.showing().state == PlayState::Paused));
        let paused = listened(&shared, &record.identity).expect("a pause is written").1;
        assert!(paused >= second.as_millis() as i64, "{paused}");

        player.skip_by(false);
        let back = listened(&shared, &record.identity).expect("a skip is written").1;
        assert_eq!(back, (paused - 15_000).max(0), "{back}");

        player.set_sleep(Some(SleepTimer::After(Duration::from_secs(300))));
        assert_eq!(player.showing().sleep.map(|s| s.remaining), Some(Duration::from_secs(300)));
        assert!(player.can_sleep_at_end_of_chapter());
        player.set_sleep(None);
        assert!(player.showing().sleep.is_none());
        assert_eq!(player.displace_voice(&path), None);
        player.stop();
        assert_eq!(player.showing().state, PlayState::Stopped);
    }

    /// `ebook-reader`, *Starting playback*, *Reaching the end of a chapter*, *Controlling it
    /// without going back* and *Opening a different publication*: the voice speaks a chapter's
    /// sentences, goes on into the next chapter, steps back a sentence, names the chapter on the
    /// second line, and stops with a sentence that names the book when another one opens.
    /// Needs speech-dispatcher: `headless-proof.sh player::` runs it.
    #[test]
    fn a_voice_reads_on_across_chapters_and_stops_for_another_book() {
        let context = glib::MainContext::new();
        context
            .with_thread_default(voice_across_chapters)
            .expect("the context is this thread's");
    }

    fn voice_across_chapters() {
        if !speech_available() {
            eprintln!("skipped: no speech-dispatcher");
            return;
        }
        let shared = crate::app::App::for_tests();
        let player = Player::new(&shared);
        let chapter = |href: &str, title: &str, sentences: &[&str]| SpokenChapter {
            href: href.to_owned(),
            title: title.to_owned(),
            sentences: sentences.iter().map(|s| (*s).to_owned()).collect(),
        };
        let book = VoiceBook {
            title: "Fixture".to_owned(),
            path: PathBuf::from("/books/fixture.epub"),
            key: "fixture".to_owned(),
            series: None,
            chapters: vec![
                chapter("one.xhtml", "One", &["First.", "Second."]),
                chapter("blank.xhtml", "Blank", &[]),
                chapter("two.xhtml", "Two", &["Third."]),
            ],
            part: 0,
        };
        player.read_aloud(book).expect("the voice starts");
        let showing = player.showing();
        assert!(showing.voice && showing.can_skip);
        assert_eq!(showing.subtitle, "One");
        assert_eq!(showing.spoken, Some(("one.xhtml".to_owned(), "First.".to_owned())));
        player.skip_by(true);
        assert_eq!(player.showing().spoken.map(|s| s.1).as_deref(), Some("Second."));
        player.skip_by(true);
        let showing = player.showing();
        assert_eq!(showing.spoken, Some(("two.xhtml".to_owned(), "Third.".to_owned())));
        assert_eq!(showing.subtitle, "Two");
        player.skip_by(false);
        assert_eq!(player.showing().spoken.map(|s| s.1).as_deref(), Some("Second."));
        assert_eq!(player.voice_book(), Some(PathBuf::from("/books/fixture.epub")));
        assert_eq!(player.displace_voice(Path::new("/books/fixture.epub")), None);
        let notice = player.displace_voice(Path::new("/books/other.epub")).expect("a notice");
        assert!(notice.contains("Fixture"), "{notice}");
        assert_eq!(player.voice_book(), None);
    }

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
