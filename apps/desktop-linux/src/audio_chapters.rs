//! The chapter marks an audiobook file carries, read from its bytes (`audio-playback`,
//! *Chapters*): ID3v2 `CHAP` frames in an MP3 and the Nero `chpl` atom in an MP4. GStreamer's
//! demuxers turn neither into a table of contents on the 1.24 floor, so the app reads them
//! itself; `audio::read_chapters` adds the length and falls back to GStreamer's own table.
//!
//! shortcut: the QuickTime chapter text track (`tref`/`chap`) is not read; a file that carries
//! only that track lists its parts. Upgrade when such a book turns up.

use std::time::Duration;

use crate::playback::Chapter;

/// The chapters of a file's bytes, in order, each ending where the next starts; the last ends
/// at `length` when it is known. Empty when the file declares none.
pub fn of(bytes: &[u8], length: Option<Duration>) -> Vec<Chapter> {
    let mut chapters = if bytes.starts_with(b"ID3") {
        id3(bytes)
    } else {
        mp4(bytes)
    };
    chapters.sort_by_key(|chapter| chapter.start);
    let starts: Vec<Duration> = chapters.iter().map(|c| c.start).collect();
    for (at, chapter) in chapters.iter_mut().enumerate() {
        let next = starts.get(at + 1).copied().or(length);
        if chapter.end.is_none_or(|end| end <= chapter.start) {
            chapter.end = next.filter(|end| *end > chapter.start);
        }
    }
    chapters
}

/// The bytes of a file that can hold its chapters: the ID3v2 tag at its head, or its `moov`
/// box wherever it sits. The rest, the audio itself, is never read.
pub fn read_marks(path: &std::path::Path) -> std::io::Result<Vec<u8>> {
    use std::io::{Read, Seek, SeekFrom};
    let mut file = std::fs::File::open(path)?;
    let mut head = [0u8; 10];
    let read = file.read(&mut head)?;
    if read == 10 && head.starts_with(b"ID3") {
        let size = syncsafe(&head, 6).unwrap_or(0) as usize;
        let mut tag = head.to_vec();
        tag.resize(10 + size, 0);
        file.read_exact(&mut tag[10..])?;
        return Ok(tag);
    }
    let total = file.metadata()?.len();
    let mut at = 0u64;
    while at + 8 <= total {
        file.seek(SeekFrom::Start(at))?;
        let mut header = [0u8; 16];
        file.read_exact(&mut header[..8])?;
        let mut size = u64::from(be32(&header, 0).unwrap_or(0));
        if size == 1 {
            file.read_exact(&mut header[8..])?;
            size = u64::from_be_bytes(header[8..].try_into().unwrap_or([0; 8]));
        } else if size == 0 {
            size = total - at;
        }
        if size < 8 {
            break;
        }
        // A movie box past a few tens of megabytes is not a chapter list worth waiting for.
        if &header[4..8] == b"moov" && size <= 64 << 20 {
            file.seek(SeekFrom::Start(at))?;
            let mut moov = vec![0u8; usize::try_from(size).unwrap_or(0)];
            file.read_exact(&mut moov)?;
            return Ok(moov);
        }
        at += size;
    }
    Ok(Vec::new())
}

fn be32(bytes: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_be_bytes(bytes.get(at..at + 4)?.try_into().ok()?))
}

fn syncsafe(bytes: &[u8], at: usize) -> Option<u32> {
    let b = bytes.get(at..at + 4)?;
    Some(
        b.iter()
            .fold(0u32, |acc, byte| (acc << 7) | u32::from(byte & 0x7f)),
    )
}

/// An ID3v2 text frame's body: an encoding byte, then the text.
fn id3_text(body: &[u8]) -> Option<String> {
    let (&encoding, text) = body.split_first()?;
    let text = match encoding {
        1 | 2 => {
            let mut units: Vec<u16> = text
                .as_chunks::<2>()
                .0
                .iter()
                .map(|pair| u16::from_be_bytes(*pair))
                .collect();
            if encoding == 1 && units.first() == Some(&0xFFFE) {
                units = units.iter().map(|unit| unit.swap_bytes()).collect();
            }
            let units: Vec<u16> = units
                .into_iter()
                .filter(|unit| *unit != 0xFEFF)
                .take_while(|unit| *unit != 0)
                .collect();
            String::from_utf16_lossy(&units)
        }
        3 => String::from_utf8_lossy(text.split(|b| *b == 0).next().unwrap_or(&[])).into_owned(),
        _ => text
            .iter()
            .take_while(|b| **b != 0)
            .map(|b| char::from(*b))
            .collect(),
    };
    Some(text.trim().to_owned()).filter(|text| !text.is_empty())
}

/// The frames of an ID3v2 tag or of a `CHAP` frame's embedded part: id, body.
fn id3_frames(bytes: &[u8], major: u8) -> Vec<(&[u8], &[u8])> {
    let mut frames = Vec::new();
    let mut at = 0;
    while at + 10 <= bytes.len() && bytes[at] != 0 {
        let id = &bytes[at..at + 4];
        let size = if major >= 4 {
            syncsafe(bytes, at + 4)
        } else {
            be32(bytes, at + 4)
        };
        let Some(size) = size.map(|size| size as usize) else {
            break;
        };
        let Some(body) = bytes.get(at + 10..at + 10 + size) else {
            break;
        };
        frames.push((id, body));
        at += 10 + size;
    }
    frames
}

fn id3(bytes: &[u8]) -> Vec<Chapter> {
    let (Some(&major), Some(&flags), Some(size)) = (bytes.get(3), bytes.get(5), syncsafe(bytes, 6))
    else {
        return Vec::new();
    };
    if !(3..=4).contains(&major) {
        return Vec::new();
    }
    let Some(mut tag) = bytes.get(10..10 + size as usize) else {
        return Vec::new();
    };
    // An extended header comes first when the flag says so.
    if flags & 0x40 != 0 {
        let extended = if major >= 4 {
            syncsafe(tag, 0)
        } else {
            be32(tag, 0).map(|n| n + 4)
        };
        tag = extended.and_then(|n| tag.get(n as usize..)).unwrap_or(&[]);
    }
    id3_frames(tag, major)
        .into_iter()
        .filter(|(id, _)| *id == b"CHAP")
        .filter_map(|(_, body)| {
            let id_end = body.iter().position(|b| *b == 0)?;
            let start = be32(body, id_end + 1)?;
            let end = be32(body, id_end + 5)?;
            let embedded = body.get(id_end + 17..).unwrap_or(&[]);
            let title = id3_frames(embedded, major)
                .into_iter()
                .find(|(id, _)| *id == b"TIT2")
                .and_then(|(_, text)| id3_text(text));
            Some(Chapter {
                title,
                start: Duration::from_millis(u64::from(start)),
                end: Some(Duration::from_millis(u64::from(end))),
                ..Chapter::default()
            })
        })
        .collect()
}

/// The boxes of an MP4 level: type, body.
fn boxes(bytes: &[u8]) -> Vec<(&[u8], &[u8])> {
    let mut found = Vec::new();
    let mut at = 0;
    while let Some(size) = be32(bytes, at) {
        let kind = &bytes[at + 4..(at + 8).min(bytes.len())];
        let (header, size) = match size {
            1 => {
                let large = bytes
                    .get(at + 8..at + 16)
                    .and_then(|b| b.try_into().ok())
                    .map(u64::from_be_bytes);
                (16, large.and_then(|n| usize::try_from(n).ok()).unwrap_or(0))
            }
            0 => (8, bytes.len() - at),
            n => (8, n as usize),
        };
        if size < header {
            break;
        }
        let Some(body) = bytes.get(at + header..at + size) else {
            break;
        };
        found.push((kind, body));
        at += size;
    }
    found
}

fn mp4(bytes: &[u8]) -> Vec<Chapter> {
    let child = |level: &[u8], name: &[u8]| -> Option<Vec<u8>> {
        boxes(level)
            .into_iter()
            .find(|(kind, _)| *kind == name)
            .map(|(_, body)| body.to_vec())
    };
    let Some(chpl) = child(bytes, b"moov")
        .and_then(|moov| child(&moov, b"udta"))
        .and_then(|udta| child(&udta, b"chpl"))
    else {
        return Vec::new();
    };
    let version = chpl.first().copied().unwrap_or(0);
    let mut at = if version > 0 { 8 } else { 4 };
    let count = chpl.get(at).copied().unwrap_or(0);
    at += 1;
    let mut chapters = Vec::new();
    for _ in 0..count {
        let Some(start) = chpl
            .get(at..at + 8)
            .and_then(|b| b.try_into().ok())
            .map(u64::from_be_bytes)
        else {
            break;
        };
        let length = usize::from(chpl.get(at + 8).copied().unwrap_or(0));
        let Some(title) = chpl.get(at + 9..at + 9 + length) else {
            break;
        };
        let title = String::from_utf8_lossy(title).trim().to_owned();
        // Hundreds of nanoseconds.
        chapters.push(Chapter {
            title: Some(title).filter(|t| !t.is_empty()),
            start: Duration::from_nanos(start.saturating_mul(100)),
            ..Chapter::default()
        });
        at += 9 + length;
    }
    chapters
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> Vec<u8> {
        std::fs::read(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../packages/test-fixtures/audiobooks")
                .join(name),
        )
        .expect("the fixture")
    }

    /// `audio-playback`, *Chapters*: the corpus MP3's `CHAP` frames and the M4B's `chpl` atom
    /// read as chapters in order, each ending where the next starts; a file with none has none.
    #[test]
    fn the_corpus_audiobooks_name_their_chapters() {
        for name in ["id3-chapters.mp3", "chaptered.m4b"] {
            let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../packages/test-fixtures/audiobooks")
                .join(name);
            let marks = read_marks(&path).expect("the fixture");
            assert!(
                marks.len() < fixture(name).len(),
                "{name}: the audio was read too"
            );
            let chapters = of(&marks, Some(Duration::from_secs(6)));
            assert!(chapters.len() >= 2, "{name}: {chapters:?}");
            assert_eq!(chapters[0].start, Duration::ZERO, "{name}");
            assert!(
                chapters
                    .iter()
                    .all(|c| c.title.is_some() && c.end.is_some()),
                "{name}: {chapters:?}"
            );
            assert!(
                chapters.windows(2).all(|p| p[0].end == Some(p[1].start)),
                "{name}: {chapters:?}"
            );
        }
        assert!(of(&fixture("unchaptered.m4a"), None).is_empty());
        assert!(of(b"ID3\x04\x00\x00\x00\x00\x00\x05abc", None).is_empty());
        assert!(of(b"\x00\x00\x00\x08moov", None).is_empty());
    }
}
