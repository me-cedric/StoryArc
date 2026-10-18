//! The player's rules, with no GTK and no GStreamer in them (`audio-playback`, *Playback
//! controls* and *Chapters before the first minute*): chapters and their marks, the speed stops
//! and the speed a publication remembers, the sleep timer and its fade, a skip that crosses into
//! the neighbouring part, and when a lost route pauses. The Linux copy of the phones' `Playback`
//! package (`PlaybackSpeed`, `SleepTimer`, `SkipIntervals`, `ChapterProgress`).

use std::time::Duration;

use crate::player::clock;
use crate::strings::{tr, tr_args};

/// One stop of a book's chapter list: a chapter of a file, from its marks, or a part of a
/// folder, or a chapter a voice reads. `start` and `end` are within its part.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Chapter {
    pub title: Option<String>,
    pub part: usize,
    pub start: Duration,
    pub end: Option<Duration>,
}

impl Chapter {
    pub fn duration(&self) -> Option<Duration> {
        self.end.map(|end| end.saturating_sub(self.start))
    }
}

/// Where a chapter stands against the listener.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mark {
    Finished,
    /// In progress, with what is left of it when its length is known.
    InProgress(Option<Duration>),
    Ahead,
}

/// The chapter a place is inside: the last one starting at or before it.
pub fn chapter_at(chapters: &[Chapter], part: usize, position: Duration) -> Option<usize> {
    chapters.iter().rposition(|chapter| {
        chapter.part < part || (chapter.part == part && chapter.start <= position)
    })
}

/// The phones' `ChapterProgress` rule: before the current one finished, the current one in
/// progress with what is left, the rest ahead; all finished once the book has been heard.
pub fn mark(
    chapters: &[Chapter],
    index: usize,
    current: usize,
    position: Duration,
    finished: bool,
) -> Mark {
    if finished || index < current {
        return Mark::Finished;
    }
    if index > current {
        return Mark::Ahead;
    }
    Mark::InProgress(chapters[index].end.map(|end| end.saturating_sub(position)))
}

/// A chapter's name: its own title, or *Part n*.
pub fn chapter_name(chapter: &Chapter, index: usize) -> String {
    chapter
        .title
        .clone()
        .filter(|title| !title.trim().is_empty())
        .unwrap_or_else(|| tr_args("player.part.number %d", "Part %d", &[&(index + 1)]))
}

/// One row of a chapter list, read as one control: the name, the duration or what is left, and
/// the mark (`audio-playback`, *Chapters*).
pub fn chapter_row(chapter: &Chapter, index: usize, mark: Mark) -> String {
    let name = chapter_name(chapter, index);
    let mut parts = vec![name];
    match mark {
        Mark::InProgress(left) => {
            if let Some(left) = left {
                parts.push(tr_args(
                    "player.chapter.remaining %s",
                    "%s left",
                    &[&clock(left)],
                ));
            }
            parts.push(tr("player.chapter.inProgress", "In progress"));
        }
        Mark::Finished => {
            if let Some(duration) = chapter.duration() {
                parts.push(clock(duration));
            }
            parts.push(tr("player.chapter.finished", "Finished"));
        }
        Mark::Ahead => {
            if let Some(duration) = chapter.duration() {
                parts.push(clock(duration));
            }
        }
    }
    parts.join(" · ")
}

/// What an audiobook's page lists (`audio-playback`, *Chapters before the first minute*): its
/// chapters with their marks, or, for one part with no marks, its length alone.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Listing {
    Chapters(Vec<String>),
    Length(Option<Duration>),
}

/// The page's list, marked against where the listener stopped, when they have.
pub fn listing(chapters: &[Chapter], stopped: Option<(usize, Duration)>) -> Listing {
    if chapters.len() < 2 {
        return Listing::Length(chapters.first().and_then(|chapter| chapter.end));
    }
    let current =
        stopped.and_then(|(part, offset)| Some((chapter_at(chapters, part, offset)?, offset)));
    Listing::Chapters(
        chapters
            .iter()
            .enumerate()
            .map(|(index, chapter)| {
                let mark = match current {
                    Some((current, offset)) => mark(chapters, index, current, offset, false),
                    None => Mark::Ahead,
                };
                chapter_row(chapter, index, mark)
            })
            .collect(),
    )
}

/// The primary action: *Listen* for a book never started, else *Continue* and the chapter it
/// resumes inside.
pub fn resume_label(chapters: &[Chapter], stopped: Option<(usize, Duration)>) -> String {
    let Some((part, offset)) = stopped else {
        return tr("detail.listen", "Listen");
    };
    match chapter_at(chapters, part, offset).filter(|_| chapters.len() > 1) {
        Some(index) => tr_args(
            "detail.continueListening.in %s",
            "Continue %s",
            &[&chapter_name(&chapters[index], index)],
        ),
        None => tr("detail.continueListening", "Continue listening"),
    }
}

/// The speeds a picker offers, half to triple, as the phones' `PlaybackSpeed.stops`.
pub const SPEEDS: [f64; 9] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

pub fn clamp_speed(rate: f64) -> f64 {
    if rate.is_finite() {
        rate.clamp(0.5, 3.0)
    } else {
        1.0
    }
}

/// The speed stated as a number: `1×`, `1.5×`.
pub fn speed_text(rate: f64) -> String {
    let number = format!("{:.2}", clamp_speed(rate));
    let number = number.trim_end_matches('0').trim_end_matches('.');
    tr_args("player.speed.value %s", "%s×", &[&number])
}

/// The speed each publication was last heard at, and the series it is in, so a book of the same
/// series starts at it (`audio-playback`, *Speed*).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Speeds {
    entries: Vec<(String, String, f64)>,
}

impl Speeds {
    pub fn speed(&self, publication: &str, series: Option<&str>) -> f64 {
        let own = self
            .entries
            .iter()
            .rev()
            .find(|(id, _, _)| id == publication);
        let shared = || {
            series
                .filter(|s| !s.is_empty())
                .and_then(|series| self.entries.iter().rev().find(|(_, of, _)| of == series))
        };
        own.or_else(shared).map_or(1.0, |(_, _, rate)| *rate)
    }

    pub fn remember(&mut self, publication: &str, series: Option<&str>, rate: f64) {
        self.entries.retain(|(id, _, _)| id != publication);
        self.entries.push((
            publication.to_owned(),
            series.unwrap_or("").to_owned(),
            clamp_speed(rate),
        ));
    }

    pub fn save(&self) -> String {
        self.entries
            .iter()
            .map(|(id, series, rate)| format!("{rate}\t{series}\t{id}\n"))
            .collect()
    }

    pub fn restore(text: &str) -> Self {
        let entries = text
            .lines()
            .filter_map(|line| {
                let mut fields = line.splitn(3, '\t');
                let rate = fields.next()?.parse::<f64>().ok()?;
                let series = fields.next()?.to_owned();
                let id = fields.next()?.to_owned();
                Some((id, series, clamp_speed(rate)))
            })
            .collect();
        Self { entries }
    }
}

/// The fixed skips: fifteen seconds back, thirty forward.
pub const SKIP_BACK: Duration = Duration::from_secs(15);
pub const SKIP_FORWARD: Duration = Duration::from_secs(30);

/// Where a skip lands across the parts of a book: past the start or the end of one it goes on
/// into the neighbour, held at the book's two ends (`audio-playback`, *Skipping*). `lengths` are
/// the parts' lengths as far as they are known; an unknown length stops a skip at that part.
pub fn skip(
    lengths: &[Option<Duration>],
    part: usize,
    offset: Duration,
    forward: bool,
) -> (usize, Duration) {
    let (mut part, mut offset) = (part, offset);
    if forward {
        let mut left = SKIP_FORWARD;
        loop {
            let Some(length) = lengths.get(part).copied().flatten() else {
                return (part, offset + left);
            };
            let room = length.saturating_sub(offset);
            if left < room || part + 1 >= lengths.len() {
                return (part, (offset + left).min(length));
            }
            left -= room;
            part += 1;
            offset = Duration::ZERO;
        }
    }
    let mut left = SKIP_BACK;
    loop {
        if left <= offset || part == 0 {
            return (part, offset.saturating_sub(left));
        }
        left -= offset;
        part -= 1;
        let Some(length) = lengths[part] else {
            return (part, Duration::ZERO);
        };
        offset = length;
    }
}

/// What the sleep timer waits for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SleepTimer {
    After(Duration),
    EndOfChapter,
}

/// The durations offered, five minutes to an hour.
pub const SLEEP_MINUTES: [u64; 5] = [5, 15, 30, 45, 60];

/// The fade before the timer stops a narrated book, and a voice's shorter one.
pub const FADE: Duration = Duration::from_secs(30);
pub const VOICE_FADE: Duration = Duration::from_secs(10);

/// A running sleep timer.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Countdown {
    pub timer: SleepTimer,
    pub remaining: Duration,
}

impl Countdown {
    /// `left_in_chapter` is what is left of the chapter playing, when its length is known; a
    /// timer for the end of a chapter with none known does not start.
    pub fn of(timer: SleepTimer, left_in_chapter: Option<Duration>) -> Option<Self> {
        let remaining = match timer {
            SleepTimer::After(duration) => Some(duration).filter(|d| !d.is_zero()),
            SleepTimer::EndOfChapter => left_in_chapter,
        }?;
        Some(Self { timer, remaining })
    }

    /// The countdown after `elapsed` of playing.
    pub fn ticked(self, elapsed: Duration, left_in_chapter: Option<Duration>) -> Self {
        let remaining = match self.timer {
            SleepTimer::After(_) => self.remaining.saturating_sub(elapsed),
            SleepTimer::EndOfChapter => left_in_chapter.unwrap_or(self.remaining),
        };
        Self { remaining, ..self }
    }

    pub fn has_elapsed(self) -> bool {
        self.remaining.is_zero()
    }

    /// The volume over the last `window`: one before it, falling to nothing at the end.
    pub fn gain(self, window: Duration) -> f64 {
        if self.remaining >= window {
            return 1.0;
        }
        (self.remaining.as_secs_f64() / window.as_secs_f64()).clamp(0.0, 1.0)
    }
}

/// Where a book the timer stopped is recorded: a fade's length earlier, so resuming starts a
/// little before where the listener drifted off.
pub fn recorded_after_fade(offset: Duration) -> Duration {
    offset.saturating_sub(FADE)
}

/// `audio-playback`, *Headphones removed*: an audio output going away while the book plays
/// pauses it; a new one appearing never starts it again.
pub fn pauses_when_output_goes(removed: bool, playing: bool) -> bool {
    removed && playing
}

/// The coverless artwork, as an SVG the desktop's media controls can show (`audio-playback`,
/// *A publication with no cover*): the publication's kind as a symbol over the format's name,
/// never the title. The player draws the same symbol and name with its own widgets.
pub fn coverless_svg(audio: bool, format: &str) -> String {
    let symbol = if audio {
        // Headphones: a band and two ear cups.
        r##"<path d="M70 150 v-30 a58 58 0 0 1 116 0 v30" fill="none" stroke="#3d3846" stroke-width="12" stroke-linecap="round"/><rect x="58" y="138" width="30" height="50" rx="10" fill="#3d3846"/><rect x="168" y="138" width="30" height="50" rx="10" fill="#3d3846"/>"##
    } else {
        // A closed book.
        r##"<rect x="78" y="70" width="100" height="124" rx="8" fill="none" stroke="#3d3846" stroke-width="12"/><line x1="98" y1="70" x2="98" y2="194" stroke="#3d3846" stroke-width="8"/>"##
    };
    let format: String = format
        .chars()
        .map(|c| match c {
            '<' | '>' | '&' | '"' => ' ',
            c => c,
        })
        .collect();
    format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><rect width="256" height="256" rx="24" fill="#deddda"/>{symbol}<text x="128" y="230" text-anchor="middle" font-family="sans-serif" font-size="24" font-weight="bold" fill="#3d3846">{format}</text></svg>"##
    )
}

#[cfg(test)]
mod tests {

    /// *A publication with no cover*: the kind as a symbol over the format's name, and no title.
    #[test]
    fn the_coverless_artwork_names_the_format_and_never_the_title() {
        let audio = coverless_svg(true, "M4B");
        assert!(audio.starts_with("<svg") && audio.contains(">M4B</text>"));
        assert_ne!(audio, coverless_svg(false, "M4B"));
        assert!(!coverless_svg(true, "<b>").contains("<b>"));
    }
    use super::*;

    fn secs(s: u64) -> Duration {
        Duration::from_secs(s)
    }

    fn chapters() -> Vec<Chapter> {
        vec![
            Chapter {
                title: Some("One".into()),
                part: 0,
                start: secs(0),
                end: Some(secs(60)),
            },
            Chapter {
                title: None,
                part: 0,
                start: secs(60),
                end: Some(secs(200)),
            },
            Chapter {
                title: Some("Three".into()),
                part: 1,
                start: secs(0),
                end: Some(secs(60)),
            },
        ]
    }

    /// `audio-playback`, *Chapters*: finished before, in progress with what is left, nothing
    /// ahead; the name, the length and the mark read as one row.
    #[test]
    fn chapters_are_marked_and_read_as_one_row() {
        let all = chapters();
        let at = secs(90);
        let current = chapter_at(&all, 0, at).unwrap();
        assert_eq!(current, 1);
        assert_eq!(chapter_at(&all, 1, secs(5)), Some(2));
        assert_eq!(mark(&all, 0, current, at, false), Mark::Finished);
        assert_eq!(
            mark(&all, 1, current, at, false),
            Mark::InProgress(Some(secs(110)))
        );
        assert_eq!(mark(&all, 2, current, at, false), Mark::Ahead);
        assert_eq!(mark(&all, 2, current, at, true), Mark::Finished);
        assert_eq!(
            chapter_row(&all[0], 0, Mark::Finished),
            "One · 1:00 · Finished"
        );
        assert_eq!(
            chapter_row(&all[1], 1, Mark::InProgress(Some(secs(110)))),
            "Part 2 · 1:50 left · In progress"
        );
        assert_eq!(chapter_row(&all[2], 2, Mark::Ahead), "Three · 1:00");
    }

    /// *Speed*: half to triple as numbers, remembered for the book and offered to its series.
    #[test]
    fn a_speed_is_a_number_kept_for_the_book_and_its_series() {
        assert_eq!(speed_text(1.0), "1×");
        assert_eq!(speed_text(1.5), "1.5×");
        assert_eq!(speed_text(9.0), "3×");
        assert_eq!((SPEEDS[0], SPEEDS[SPEEDS.len() - 1]), (0.5, 3.0));
        let mut speeds = Speeds::default();
        speeds.remember("a", Some("Saga"), 1.75);
        assert_eq!(speeds.speed("a", None), 1.75);
        assert_eq!(speeds.speed("b", Some("Saga")), 1.75);
        assert_eq!(speeds.speed("c", Some("Other")), 1.0);
        speeds.remember("a", Some("Saga"), 1.25);
        assert_eq!(Speeds::restore(&speeds.save()), speeds);
        assert_eq!(Speeds::restore("x\ty\tz\n").speed("z", None), 1.0);
    }

    /// *Skipping*: fifteen back, thirty forward, into the neighbouring part at a boundary and
    /// held at the book's ends.
    #[test]
    fn a_skip_crosses_into_the_neighbouring_part_and_stops_at_the_ends() {
        let lengths = [Some(secs(100)), Some(secs(20)), Some(secs(100))];
        assert_eq!(skip(&lengths, 0, secs(50), true), (0, secs(80)));
        assert_eq!(skip(&lengths, 0, secs(90), true), (2, secs(0)));
        assert_eq!(skip(&lengths, 0, secs(95), true), (2, secs(5)));
        assert_eq!(skip(&lengths, 2, secs(90), true), (2, secs(100)));
        assert_eq!(skip(&lengths, 2, secs(5), false), (1, secs(10)));
        assert_eq!(skip(&lengths, 2, secs(30), false), (2, secs(15)));
        assert_eq!(skip(&lengths, 0, secs(5), false), (0, secs(0)));
    }

    /// *Sleep timer*: a duration or the end of the chapter, counting down while playing, a fade
    /// over the last thirty seconds, and the place recorded a fade earlier.
    #[test]
    fn the_sleep_timer_counts_down_fades_and_records_a_little_earlier() {
        let timer = Countdown::of(SleepTimer::After(secs(300)), None).unwrap();
        let later = timer.ticked(secs(285), None);
        assert_eq!(later.remaining, secs(15));
        assert!((later.gain(FADE) - 0.5).abs() < 1e-9);
        assert!(later.ticked(secs(20), None).has_elapsed());
        assert_eq!(timer.gain(FADE), 1.0);
        assert!(Countdown::of(SleepTimer::EndOfChapter, None).is_none());
        let chapter = Countdown::of(SleepTimer::EndOfChapter, Some(secs(40))).unwrap();
        assert_eq!(chapter.ticked(secs(1), Some(secs(12))).remaining, secs(12));
        assert_eq!(recorded_after_fade(secs(100)), secs(70));
        assert_eq!(recorded_after_fade(secs(10)), secs(0));
    }

    /// *The chapter list on the publication's page*, *An audiobook with one part* and *The
    /// primary action says where it will resume*.
    #[test]
    fn the_page_lists_chapters_or_a_length_and_names_where_it_resumes() {
        let all = chapters();
        assert_eq!(
            listing(&all, Some((0, secs(90)))),
            Listing::Chapters(vec![
                "One · 1:00 · Finished".into(),
                "Part 2 · 1:50 left · In progress".into(),
                "Three · 1:00".into(),
            ])
        );
        assert_eq!(
            listing(&all, None),
            Listing::Chapters(vec![
                "One · 1:00".into(),
                "Part 2 · 2:20".into(),
                "Three · 1:00".into()
            ])
        );
        let single = [Chapter {
            end: Some(secs(3600)),
            ..Chapter::default()
        }];
        assert_eq!(listing(&single, None), Listing::Length(Some(secs(3600))));
        assert_eq!(resume_label(&all, None), "Listen");
        assert_eq!(resume_label(&all, Some((1, secs(5)))), "Continue Three");
        assert_eq!(
            resume_label(&single, Some((0, secs(5)))),
            "Continue listening"
        );
    }

    /// *Headphones removed*: an output going away pauses a playing book; nothing resumes it.
    #[test]
    fn an_output_going_away_pauses_and_nothing_resumes() {
        assert!(pauses_when_output_goes(true, true));
        assert!(!pauses_when_output_goes(true, false));
        assert!(!pauses_when_output_goes(false, true));
    }
}
