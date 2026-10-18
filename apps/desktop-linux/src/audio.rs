//! Audio playback through GStreamer (task 4.12, the spike design.md Decision 5b assumed;
//! `audio-playback`, Playback controls). One `GstPlay` over playbin: a file plays, pauses,
//! seeks, changes rate and reports its position and duration. The player's state is read
//! from the play bus on the GLib main loop, so the window and MPRIS see one truth.
//!
//! Where GStreamer cannot be initialised, or the file's decoder is not installed, the
//! error names it and the control stays absent (`desktop-experience`, A Linux system
//! without an optional service). The audio sink is the system's own; a test with no
//! sound device asks for a `fakesink` that keeps the clock.

use std::cell::{Cell, RefCell};
use std::path::Path;
use std::rc::Rc;
use std::time::Duration;

use gst::prelude::*;
use gstreamer as gst;
use gstreamer_play as gst_play;
use gtk::glib;

/// The chapters a file declares, and its length, read by prerolling it once on a silent pipeline
/// (`audio-playback`, *Chapters*): the marks `audio_chapters` reads from the file, else the table
/// of contents a demuxer sends down. No chapter is an empty list, never an error. Blocks for at
/// most ten seconds: call it from a worker.
pub fn read_chapters(
    path: &Path,
) -> Result<(Vec<crate::playback::Chapter>, Option<Duration>), String> {
    gst::init().map_err(|error| format!("GStreamer is not available: {error}"))?;
    let uri = glib::filename_to_uri(path, None).map_err(|error| error.to_string())?;
    let silent = || {
        gst::ElementFactory::make("fakesink")
            .build()
            .map_err(|error| format!("no fakesink: {error}"))
    };
    // The table of contents travels down to the sink as a sticky event; playbin posts none.
    let audio_sink = silent()?;
    let found: std::sync::Arc<std::sync::Mutex<Option<gst::Toc>>> = std::sync::Arc::default();
    if let Some(pad) = audio_sink.static_pad("sink") {
        let found = found.clone();
        pad.add_probe(gst::PadProbeType::EVENT_DOWNSTREAM, move |_, info| {
            if let Some(gst::PadProbeData::Event(event)) = &info.data
                && let gst::EventView::Toc(toc) = event.view()
                && let Ok(mut slot) = found.lock()
            {
                *slot = Some(toc.toc().0.to_owned());
            }
            gst::PadProbeReturn::Ok
        });
    }
    let pipeline = gst::ElementFactory::make("playbin")
        .property("uri", uri.as_str())
        .property("audio-sink", &audio_sink)
        .property("video-sink", silent()?)
        .build()
        .map_err(|error| format!("no playbin: {error}"))?;
    let bus = pipeline.bus().ok_or("the pipeline has no bus")?;
    pipeline
        .set_state(gst::State::Paused)
        .map_err(|error| format!("{}: {error}", path.display()))?;
    let mut toc: Option<gst::Toc> = None;
    let outcome = loop {
        let Some(message) = bus.timed_pop(gst::ClockTime::from_seconds(10)) else {
            break Err(format!("{}: no answer in ten seconds", path.display()));
        };
        match message.view() {
            gst::MessageView::Toc(found) => toc = Some(found.toc().0),
            gst::MessageView::AsyncDone(_) => break Ok(()),
            gst::MessageView::Error(error) => {
                break Err(format!("{}: {}", path.display(), error.error()));
            }
            _ => {}
        }
    };
    let length = pipeline
        .query_duration::<gst::ClockTime>()
        .map(|length| Duration::from_nanos(length.nseconds()));
    let _ = pipeline.set_state(gst::State::Null);
    outcome?;
    if toc.is_none() {
        toc = found.lock().ok().and_then(|slot| slot.clone());
    }
    let marks = crate::audio_chapters::read_marks(path).unwrap_or_default();
    let mut chapters = crate::audio_chapters::of(&marks, length);
    if let Some(toc) = toc.filter(|_| chapters.is_empty()) {
        let mut entries: Vec<gst::TocEntry> = toc.entries();
        while let Some(entry) = entries.first().cloned() {
            entries.remove(0);
            if entry.entry_type() == gst::TocEntryType::Chapter {
                let Some((start, stop)) = entry.start_stop_times() else {
                    continue;
                };
                let title = entry.tags().and_then(|tags| {
                    tags.get::<gst::tags::Title>()
                        .map(|title| title.get().to_owned())
                });
                let nanos = |at: i64| Duration::from_nanos(u64::try_from(at).unwrap_or(0));
                chapters.push(crate::playback::Chapter {
                    title,
                    part: 0,
                    start: nanos(start),
                    end: (stop > start).then(|| nanos(stop)),
                });
            }
            entries.splice(0..0, entry.sub_entries());
        }
    }
    chapters.sort_by_key(|chapter| chapter.start);
    Ok((chapters, length))
}

/// What the player is doing, as the bus last said.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum PlayState {
    #[default]
    Stopped,
    Buffering,
    Paused,
    Playing,
}

impl PlayState {
    /// The MPRIS `PlaybackStatus` word.
    pub fn mpris(self) -> &'static str {
        match self {
            Self::Stopped => "Stopped",
            Self::Buffering | Self::Paused => "Paused",
            Self::Playing => "Playing",
        }
    }
}

/// Where the sound goes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Sink {
    /// The system's: autoaudiosink, which is PipeWire or PulseAudio on a desktop.
    System,
    /// A `fakesink` that keeps the clock: a host with no sound device, such as a container.
    Null,
}

/// Something the player tells its listeners.
#[derive(Clone, Debug, PartialEq)]
pub enum PlayerEvent {
    State(PlayState),
    Position(Duration),
    Duration(Duration),
    EndOfStream,
    /// The engine's own words: a missing decoder, an unreadable file.
    Error(String),
}

type Listener = Box<dyn Fn(&PlayerEvent)>;

pub struct AudioPlayer {
    play: gst_play::Play,
    state: Cell<PlayState>,
    listeners: RefCell<Vec<Listener>>,
    /// The bus watch lives as long as the player; dropping the guard removes the watch.
    watch: RefCell<Option<gst::bus::BusWatchGuard>>,
}

impl AudioPlayer {
    /// Starts GStreamer (once per process) and makes a player over `sink`.
    pub fn new(sink: Sink) -> Result<Rc<Self>, String> {
        gst::init().map_err(|error| format!("GStreamer is not available: {error}"))?;
        let play = gst_play::Play::new(None::<gst_play::PlayVideoRenderer>);
        if sink == Sink::Null {
            let sink = gst::ElementFactory::make("fakesink")
                .property("sync", true)
                .build()
                .map_err(|error| format!("no fakesink: {error}"))?;
            play.pipeline().set_property("audio-sink", &sink);
        }
        let player = Rc::new(Self {
            play,
            state: Cell::new(PlayState::Stopped),
            listeners: RefCell::default(),
            watch: RefCell::default(),
        });
        player.watch_bus();
        Ok(player)
    }

    /// Whether a file of this media type has a decoder here, before it is offered.
    pub fn can_decode(media_type: &str) -> bool {
        // The registry answers only once GStreamer is initialised; the bindings panic before.
        if gst::init().is_err() {
            return false;
        }
        let factory = match media_type {
            "audio/mpeg" => "mpg123audiodec",
            "audio/mp4" | "audio/x-m4a" | "audio/x-m4b" => "qtdemux",
            "audio/flac" | "audio/x-flac" => "flacdec",
            "audio/ogg" | "audio/x-vorbis+ogg" => "oggdemux",
            _ => return false,
        };
        gst::ElementFactory::find(factory).is_some()
    }

    pub fn connect(&self, listener: impl Fn(&PlayerEvent) + 'static) {
        self.listeners.borrow_mut().push(Box::new(listener));
    }

    #[cfg(test)]
    pub fn state(&self) -> PlayState {
        self.state.get()
    }

    /// Loads a file. Playback starts with [`play`](Self::play).
    pub fn load(&self, path: &Path) {
        let uri = glib::filename_to_uri(path, None)
            .map(|uri| uri.to_string())
            .unwrap_or_else(|_| format!("file://{}", path.display()));
        self.play.set_uri(Some(&uri));
    }

    pub fn play(&self) {
        self.play.play();
    }

    /// The volume, nothing to one: the sleep timer's fade.
    pub fn set_volume(&self, volume: f64) {
        self.play.set_volume(volume.clamp(0.0, 1.0));
    }

    pub fn pause(&self) {
        self.play.pause();
    }

    pub fn stop(&self) {
        self.play.stop();
        self.set_state(PlayState::Stopped);
    }

    pub fn toggle(&self) {
        match self.state.get() {
            PlayState::Playing => self.pause(),
            _ => self.play(),
        }
    }

    pub fn seek(&self, to: Duration) {
        self.play.seek(gst::ClockTime::from_nseconds(
            to.as_nanos().min(u128::from(u64::MAX)) as u64,
        ));
    }

    /// Skips by `by`, which may be negative, clamped to the file.
    pub fn skip(&self, by: i64) {
        let now = self.position().unwrap_or_default().as_secs() as i64;
        let duration = self.duration().map_or(i64::MAX, |d| d.as_secs() as i64);
        let target = (now + by).clamp(0, duration);
        self.seek(Duration::from_secs(target as u64));
    }

    pub fn set_rate(&self, rate: f64) {
        self.play.set_rate(rate.clamp(0.5, 3.0));
    }

    #[cfg(test)]
    pub fn rate(&self) -> f64 {
        self.play.rate()
    }

    pub fn position(&self) -> Option<Duration> {
        self.play
            .position()
            .map(|time| Duration::from_nanos(time.nseconds()))
    }

    pub fn duration(&self) -> Option<Duration> {
        self.play
            .duration()
            .map(|time| Duration::from_nanos(time.nseconds()))
    }

    fn set_state(&self, state: PlayState) {
        if self.state.replace(state) != state {
            self.emit(&PlayerEvent::State(state));
        }
    }

    fn emit(&self, event: &PlayerEvent) {
        for listener in self.listeners.borrow().iter() {
            listener(event);
        }
    }

    /// Reads the play bus on the main loop and tells the listeners.
    fn watch_bus(self: &Rc<Self>) {
        let weak = Rc::downgrade(self);
        let bus = self.play.message_bus();
        let guard = bus.add_watch_local(move |_, message| {
            let Some(player) = weak.upgrade() else {
                return glib::ControlFlow::Break;
            };
            if let Ok(parsed) = gst_play::PlayMessage::parse(message) {
                player.on_message(&parsed);
            }
            glib::ControlFlow::Continue
        });
        *self.watch.borrow_mut() = guard.ok();
    }

    fn on_message(&self, message: &gst_play::PlayMessage<'_>) {
        use gst_play::PlayMessage;
        match message {
            PlayMessage::StateChanged(changed) => {
                let state = match changed.state() {
                    gst_play::PlayState::Playing => PlayState::Playing,
                    gst_play::PlayState::Paused => PlayState::Paused,
                    gst_play::PlayState::Buffering => PlayState::Buffering,
                    _ => PlayState::Stopped,
                };
                self.set_state(state);
            }
            PlayMessage::PositionUpdated(updated) => {
                if let Some(position) = updated.position() {
                    self.emit(&PlayerEvent::Position(Duration::from_nanos(
                        position.nseconds(),
                    )));
                }
            }
            PlayMessage::DurationChanged(changed) => {
                if let Some(duration) = changed.duration() {
                    self.emit(&PlayerEvent::Duration(Duration::from_nanos(
                        duration.nseconds(),
                    )));
                }
            }
            PlayMessage::EndOfStream(_) => {
                self.set_state(PlayState::Stopped);
                self.emit(&PlayerEvent::EndOfStream);
            }
            PlayMessage::Error(error) => {
                self.set_state(PlayState::Stopped);
                self.emit(&PlayerEvent::Error(error.error().to_string()));
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    //! The spike's exit: a chapter plays, seeks and reports its position, on a null sink.
    //! Skips by name where GStreamer or the MP3 decoder is not installed.

    use std::time::Instant;

    use super::*;

    fn fixture(name: &str) -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../packages/test-fixtures/audiobooks")
            .join(name)
    }

    fn pump_until(deadline: Duration, mut done: impl FnMut() -> bool) -> bool {
        let context = glib::MainContext::thread_default().unwrap_or_default();
        let end = Instant::now() + deadline;
        while Instant::now() < end {
            context.iteration(false);
            if done() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        false
    }

    /// `audio-playback`, *Chapters*: the chapters of an MP4 chapter track and of ID3 `CHAP`
    /// frames, each with its start and its end, and none for a file that declares none.
    #[test]
    fn chapters_come_from_the_files_table_of_contents() {
        if !AudioPlayer::can_decode("audio/mp4") {
            eprintln!("skipped: no MP4 demuxer");
            return;
        }
        for name in ["id3-chapters.mp3", "chaptered.m4b"] {
            let (chapters, length) = read_chapters(&fixture(name)).expect("the fixture reads");
            eprintln!("{name}: {chapters:?} {length:?}");
            assert!(chapters.len() >= 2, "{name}: {chapters:?}");
            assert_eq!(chapters[0].start, Duration::ZERO, "{name}");
            assert!(
                chapters
                    .windows(2)
                    .all(|pair| pair[0].start < pair[1].start),
                "{name}"
            );
            assert!(length.is_some(), "{name}");
        }
        let (none, length) = read_chapters(&fixture("unchaptered.m4a")).expect("the fixture reads");
        assert!(none.is_empty() && length.is_some(), "{none:?}");
    }

    #[test]
    fn the_mpris_word_follows_the_state() {
        assert_eq!(PlayState::Playing.mpris(), "Playing");
        assert_eq!(PlayState::Paused.mpris(), "Paused");
        assert_eq!(PlayState::Buffering.mpris(), "Paused");
        assert_eq!(PlayState::Stopped.mpris(), "Stopped");
    }

    #[test]
    fn a_chapter_plays_seeks_and_reports_its_position_on_a_null_sink() {
        // A main context of this test's own, as the MPRIS test has: the egress test's GTK
        // owns the default one from its thread.
        let context = glib::MainContext::new();
        context
            .with_thread_default(a_chapter_on_a_null_sink)
            .expect("the context is this thread's");
    }

    fn a_chapter_on_a_null_sink() {
        let player = match AudioPlayer::new(Sink::Null) {
            Ok(player) => player,
            Err(reason) => {
                eprintln!("skipped: {reason}");
                return;
            }
        };
        if !AudioPlayer::can_decode("audio/mpeg") {
            eprintln!("skipped: no MP3 decoder (gstreamer1.0-plugins-good)");
            return;
        }
        let events: Rc<RefCell<Vec<PlayerEvent>>> = Rc::default();
        let seen = events.clone();
        player.connect(move |event| seen.borrow_mut().push(event.clone()));

        // The three-chapter fixture is six seconds: One, Two and Three, two seconds each.
        player.load(&fixture("id3-chapters.mp3"));
        player.play();
        assert!(
            pump_until(Duration::from_secs(10), || player.state()
                == PlayState::Playing),
            "never played: {:?}",
            events.borrow()
        );
        let duration = player.duration().expect("a duration once playing");
        assert!((5..=7).contains(&duration.as_secs()), "{duration:?}");

        // Seek into chapter Two and read the position back.
        player.seek(Duration::from_millis(2500));
        assert!(
            pump_until(Duration::from_secs(5), || player
                .position()
                .is_some_and(|p| p >= Duration::from_millis(2400))),
            "the position did not follow the seek: {:?}",
            player.position()
        );
        player.pause();
        assert!(pump_until(Duration::from_secs(5), || player.state()
            == PlayState::Paused));
        let held = player.position().expect("a position while paused");
        assert!(
            held >= Duration::from_millis(2400) && held < Duration::from_secs(6),
            "{held:?}"
        );
        assert!(
            events
                .borrow()
                .iter()
                .any(|event| matches!(event, PlayerEvent::Position(_))),
            "no position report arrived"
        );
        player.set_rate(1.5);
        assert!((player.rate() - 1.5).abs() < 0.01);
        player.stop();
        assert_eq!(player.state(), PlayState::Stopped);
    }
}
