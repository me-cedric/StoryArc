//! Read-aloud through speech-dispatcher (task 4.12, the spike design.md Decision 5b
//! assumed; `ebook-reader`, Reading aloud). The daemon speaks SSIP, a line protocol over a
//! Unix socket, so this is a small client with no new dependency: connect, name the
//! client, ask for notifications, speak a text, hear BEGIN and END, stop, pause, resume,
//! set the rate, list the voices.
//!
//! Where the socket is absent and the daemon cannot be spawned, there is no speech engine
//! and the read-aloud control is absent (`desktop-experience`, A device with no speech
//! engine). The protocol parsing is pure and tests on any host; the socket half runs
//! under `scripts/headless-proof.sh`.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

/// One SSIP answer: its code and the lines before the final one, without their prefix.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Response {
    pub code: u16,
    pub lines: Vec<String>,
    pub text: String,
}

impl Response {
    pub fn is_ok(&self) -> bool {
        (200..300).contains(&self.code)
    }

    /// Reads one answer: `NNN-more` lines until `NNN text`.
    pub fn read(reader: &mut impl BufRead) -> std::io::Result<Self> {
        let mut lines = Vec::new();
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line)? == 0 {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::UnexpectedEof,
                    "speech-dispatcher closed the connection",
                ));
            }
            let line = line.trim_end_matches(['\r', '\n']);
            let (code, rest) = parse_line(line).ok_or_else(|| {
                std::io::Error::new(std::io::ErrorKind::InvalidData, format!("not SSIP: {line}"))
            })?;
            match rest {
                Rest::More(more) => lines.push(more.to_owned()),
                Rest::Final(text) => {
                    return Ok(Self {
                        code,
                        lines,
                        text: text.to_owned(),
                    });
                }
            }
        }
    }
}

enum Rest<'a> {
    More(&'a str),
    Final(&'a str),
}

fn parse_line(line: &str) -> Option<(u16, Rest<'_>)> {
    let (code, rest) = line.split_at_checked(3)?;
    let code: u16 = code.parse().ok()?;
    match rest.chars().next() {
        Some('-') => Some((code, Rest::More(&rest[1..]))),
        Some(' ') => Some((code, Rest::Final(rest[1..].trim()))),
        None => Some((code, Rest::Final(""))),
        _ => None,
    }
}

/// What the daemon tells about a message it was given.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SpeechEvent {
    Begin(u32),
    End(u32),
    Cancel(u32),
    Pause(u32),
    Resume(u32),
}

impl SpeechEvent {
    /// An event from its notification, or `None` for an answer that is not one.
    pub fn of(response: &Response) -> Option<Self> {
        let id: u32 = response.lines.first()?.trim().parse().ok()?;
        Some(match response.code {
            701 => Self::Begin(id),
            702 => Self::End(id),
            703 => Self::Cancel(id),
            704 => Self::Pause(id),
            705 => Self::Resume(id),
            _ => return None,
        })
    }
}

/// The text as SSIP takes it after `SPEAK`: a line that is one dot would end the text,
/// so it is doubled, and the terminating dot follows.
pub fn speak_body(text: &str) -> String {
    let mut body = String::with_capacity(text.len() + 8);
    for line in text.lines() {
        if line.starts_with('.') {
            body.push('.');
        }
        body.push_str(line);
        body.push_str("\r\n");
    }
    body.push_str(".\r\n");
    body
}

/// Where the daemon listens: `SPEECHD_ADDRESS` first, then the runtime directory.
pub fn socket_path() -> Option<PathBuf> {
    if let Ok(address) = std::env::var("SPEECHD_ADDRESS")
        && let Some(path) = address.strip_prefix("unix_socket:")
    {
        return Some(PathBuf::from(path));
    }
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")?;
    Some(
        PathBuf::from(runtime)
            .join("speech-dispatcher")
            .join("speechd.sock"),
    )
}

pub struct Speech {
    stream: UnixStream,
    reader: BufReader<UnixStream>,
}

impl Speech {
    /// Connects, spawning the daemon the way libspeechd does when its socket is absent.
    /// The error says there is no speech engine and why.
    pub fn connect() -> Result<Self, String> {
        let path = socket_path().ok_or("no runtime directory, so no speech-dispatcher socket")?;
        let stream = match UnixStream::connect(&path) {
            Ok(stream) => stream,
            Err(_) => {
                let _ = Command::new("speech-dispatcher")
                    .arg("--spawn")
                    .output()
                    .map_err(|error| format!("speech-dispatcher is not installed: {error}"))?;
                std::thread::sleep(Duration::from_millis(300));
                UnixStream::connect(&path)
                    .map_err(|error| format!("no speech engine at {}: {error}", path.display()))?
            }
        };
        stream
            .set_read_timeout(Some(Duration::from_secs(10)))
            .map_err(|error| error.to_string())?;
        let reader = BufReader::new(stream.try_clone().map_err(|error| error.to_string())?);
        let mut speech = Self { stream, reader };
        speech.command("SET SELF CLIENT_NAME \"user:storyarc:reader\"")?;
        speech.command("SET SELF NOTIFICATION ALL on")?;
        Ok(speech)
    }

    fn command(&mut self, line: &str) -> Result<Response, String> {
        self.stream
            .write_all(format!("{line}\r\n").as_bytes())
            .map_err(|error| error.to_string())?;
        self.answer()
    }

    /// The next answer that is not an event; events met on the way are dropped here and
    /// read by [`next_event`](Self::next_event) in normal use.
    fn answer(&mut self) -> Result<Response, String> {
        loop {
            let response = Response::read(&mut self.reader).map_err(|error| error.to_string())?;
            if SpeechEvent::of(&response).is_some() {
                continue;
            }
            if !response.is_ok() {
                return Err(format!(
                    "speech-dispatcher: {} {}",
                    response.code, response.text
                ));
            }
            return Ok(response);
        }
    }

    /// Queues a text and answers its message id.
    pub fn speak(&mut self, text: &str) -> Result<u32, String> {
        let receiving = self.command("SPEAK")?;
        if receiving.code != 230 {
            return Err(format!(
                "speech-dispatcher: {} {}",
                receiving.code, receiving.text
            ));
        }
        self.stream
            .write_all(speak_body(text).as_bytes())
            .map_err(|error| error.to_string())?;
        let queued = self.answer()?;
        queued
            .lines
            .first()
            .and_then(|id| id.trim().parse().ok())
            .ok_or_else(|| format!("no message id in: {queued:?}"))
    }

    /// Waits up to the read timeout for the next event.
    pub fn next_event(&mut self) -> Option<SpeechEvent> {
        loop {
            let response = Response::read(&mut self.reader).ok()?;
            if let Some(event) = SpeechEvent::of(&response) {
                return Some(event);
            }
        }
    }

    pub fn stop(&mut self) -> Result<(), String> {
        self.command("STOP SELF").map(|_| ())
    }

    pub fn pause(&mut self) -> Result<(), String> {
        self.command("PAUSE SELF").map(|_| ())
    }

    pub fn resume(&mut self) -> Result<(), String> {
        self.command("RESUME SELF").map(|_| ())
    }

    /// The rate, from -100 (slowest) to 100 (fastest); 0 is the voice's own.
    #[allow(dead_code)] // the full player's speed control, a later task, sets it
    pub fn set_rate(&mut self, rate: i32) -> Result<(), String> {
        self.command(&format!("SET SELF RATE {}", rate.clamp(-100, 100)))
            .map(|_| ())
    }

    /// The voices the current output module offers, as `name language variant` lines.
    #[cfg(test)]
    pub fn voices(&mut self) -> Result<Vec<String>, String> {
        Ok(self.command("LIST SYNTHESIS_VOICES")?.lines)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn answers_are_read_to_their_final_line_and_events_are_told_apart() {
        let text = "225-42\r\n225 OK MESSAGE QUEUED\r\n701-42\r\n701-user:storyarc:reader\r\n701 BEGIN\r\n";
        let mut reader = std::io::Cursor::new(text);
        let queued = Response::read(&mut reader).unwrap();
        assert_eq!(queued.code, 225);
        assert_eq!(queued.lines, ["42"]);
        assert!(queued.is_ok());
        assert_eq!(SpeechEvent::of(&queued), None);
        let begin = Response::read(&mut reader).unwrap();
        assert_eq!(SpeechEvent::of(&begin), Some(SpeechEvent::Begin(42)));
        assert!(Response::read(&mut reader).is_err(), "nothing left");
    }

    #[test]
    fn a_refusal_is_not_ok_and_a_non_ssip_line_is_an_error() {
        let mut reader = std::io::Cursor::new("500 ERR INVALID COMMAND\r\n");
        let refused = Response::read(&mut reader).unwrap();
        assert!(!refused.is_ok());
        let mut junk = std::io::Cursor::new("hello\r\n");
        assert!(Response::read(&mut junk).is_err());
    }

    #[test]
    fn the_body_doubles_a_leading_dot_and_ends_with_one() {
        assert_eq!(speak_body("One.\n.Two"), "One.\r\n..Two\r\n.\r\n");
        assert_eq!(speak_body(""), ".\r\n");
    }

    #[test]
    fn a_sentence_speaks_or_the_gap_is_named() {
        let mut speech = match Speech::connect() {
            Ok(speech) => speech,
            Err(reason) => {
                eprintln!("skipped: {reason}");
                return;
            }
        };
        let voices = speech.voices().unwrap_or_default();
        eprintln!(
            "speech: {} voices, first {:?}",
            voices.len(),
            voices.first()
        );
        speech.set_rate(10).expect("the rate is taken");
        let id = speech
            .speak("StoryArc reads aloud.")
            .expect("the sentence is queued");
        let first = speech.next_event();
        eprintln!("speech: message {id}, first event {first:?}");
        assert!(
            matches!(first, Some(SpeechEvent::Begin(got)) if got == id),
            "no BEGIN for {id}: {first:?}"
        );
        // The end of the sentence needs an audio output that finishes: on a host with no
        // sound device the module never reports it, which the spike records as the gap.
        let second = speech.next_event();
        match second {
            Some(SpeechEvent::End(got) | SpeechEvent::Cancel(got)) if got == id => {
                eprintln!("speech: END for {id}: the sentence was spoken to its end")
            }
            other => eprintln!(
                "speech: no END for {id} within the read timeout ({other:?}): the gap, no audio output here"
            ),
        }
        speech.stop().expect("stop is taken");
    }
}
