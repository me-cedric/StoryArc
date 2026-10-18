//! `storyarc-thumbnailer`: the GNOME thumbnailer for the file manager (task 5.5), for
//! source and AUR builds. `data/com.mecedric.StoryArc.thumbnailer` names it for the comic
//! types; the file manager runs `storyarc-thumbnailer -s <size> <input> <output>` and shows
//! the PNG it writes. It reads the publication's first page, else a loose cover beside it,
//! through the core, and nothing else: no store, no history, no settings. A file it cannot
//! read yields no file and a failing exit, so the manager shows the generic icon.
//!
//! A Flatpak does not ship this: `flatpak build-finish` exports desktop files, icons, D-Bus
//! services and metainfo, never `share/thumbnailers`, so the Flatpak build shows no covers.

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use gtk::prelude::*;
use gtk::{gdk, glib};
use storyarc_core::library::OpenPublication;

/// The size the manager asks for when it names none (the `.thumbnailer` passes `%s`).
const DEFAULT_SIZE: u32 = 256;

/// `-s <size> <input> <output>`, in either order of the flag and the paths.
struct Args {
    size: u32,
    input: PathBuf,
    output: PathBuf,
}

fn parse(args: &[String]) -> Result<Args, String> {
    let mut size = DEFAULT_SIZE;
    let mut paths = Vec::new();
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        if arg == "-s" || arg == "--size" {
            size = rest
                .next()
                .and_then(|text| text.parse().ok())
                .filter(|size| *size > 0)
                .ok_or("-s needs a size above 0")?;
        } else {
            paths.push(PathBuf::from(arg));
        }
    }
    match paths.as_slice() {
        [input, output] => Ok(Args {
            size,
            input: input.clone(),
            output: output.clone(),
        }),
        _ => Err("usage: storyarc-thumbnailer [-s size] <input> <output.png>".into()),
    }
}

/// The PNG of the publication's cover at most `size` on its longest edge, or why not.
fn thumbnail(input: &Path, size: u32) -> Result<Vec<u8>, String> {
    let own = OpenPublication::open(input)
        .and_then(|open| open.decode_page(0, Some(size)))
        .map_err(|error| error.to_string());
    let page = match own {
        Ok(page) => page,
        Err(reason) => {
            let loose = loose_cover(input).ok_or(reason)?;
            let bytes = std::fs::read(loose).map_err(|error| error.to_string())?;
            storyarc_core::image::decode(&bytes, Some(size)).map_err(|error| error.to_string())?
        }
    };
    // GDK's PNG writer, already linked through gtk4; it needs no display.
    let stride = page.width as usize * 4;
    let texture = gdk::MemoryTexture::new(
        i32::try_from(page.width).map_err(|error| error.to_string())?,
        i32::try_from(page.height).map_err(|error| error.to_string())?,
        gdk::MemoryFormat::R8g8b8a8,
        &glib::Bytes::from_owned(page.rgba),
        stride,
    );
    Ok(texture.save_to_png_bytes().to_vec())
}

/// A `cover`, `folder` or `poster` image beside the file: the app's `covers::loose_cover`.
fn loose_cover(path: &Path) -> Option<PathBuf> {
    let folder = if path.is_dir() { path } else { path.parent()? };
    ["cover", "folder", "poster"]
        .iter()
        .flat_map(|stem| {
            ["jpg", "jpeg", "png", "webp", "heic"]
                .iter()
                .map(move |extension| folder.join(format!("{stem}.{extension}")))
        })
        .find(|candidate| candidate.is_file())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let outcome = parse(&args).and_then(|args| {
        let png = thumbnail(&args.input, args.size)?;
        std::fs::write(&args.output, png).map_err(|error| error.to_string())
    });
    match outcome {
        Ok(()) => ExitCode::SUCCESS,
        Err(reason) => {
            eprintln!("storyarc-thumbnailer: {reason}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../packages/test-fixtures/comics")
            .join(name)
    }

    #[test]
    fn a_comic_yields_a_png_no_larger_than_the_size_asked() {
        let png = thumbnail(&fixture("single-page.cbz"), 64).expect("a cover");
        assert_eq!(&png[1..4], b"PNG");
        let (width, height) = (
            u32::from_be_bytes(png[16..20].try_into().unwrap()),
            u32::from_be_bytes(png[20..24].try_into().unwrap()),
        );
        assert!(width <= 64 && height <= 64 && width > 0 && height > 0);
    }

    #[test]
    fn a_damaged_file_yields_no_thumbnail_and_writes_nothing() {
        let folder = tempfile::tempdir().unwrap();
        let damaged = folder.path().join("damaged.cbz");
        std::fs::write(&damaged, b"not an archive at all").unwrap();
        for path in [damaged, fixture("refused.cb7"), fixture("no-such-file.cbz")] {
            let error = thumbnail(&path, 128).expect_err(&path.display().to_string());
            assert!(!error.is_empty());
        }
        // Nothing is written beside the file, and no history: the thumbnailer opens no
        // store, so the folder holds the damaged file and nothing else.
        let left: Vec<_> = std::fs::read_dir(folder.path())
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect();
        assert_eq!(left, ["damaged.cbz"]);
    }

    #[test]
    fn the_arguments_are_the_size_flag_and_two_paths() {
        let args = parse(&["-s".into(), "128".into(), "in.cbz".into(), "out.png".into()]).unwrap();
        assert_eq!(
            (args.size, args.input.as_os_str(), args.output.as_os_str()),
            (128, "in.cbz".as_ref(), "out.png".as_ref())
        );
        assert_eq!(
            parse(&["in.cbz".into(), "out.png".into()]).unwrap().size,
            DEFAULT_SIZE
        );
        assert!(parse(&["in.cbz".into()]).is_err());
        assert!(parse(&["-s".into(), "0".into(), "a".into(), "b".into()]).is_err());
    }

    #[test]
    fn the_thumbnailer_file_names_this_binary_and_the_comic_types() {
        let text = include_str!("../data/com.mecedric.StoryArc.thumbnailer");
        assert!(text.contains("Exec=storyarc-thumbnailer -s %s %i %o"));
        for kind in [
            "application/vnd.comicbook+zip",
            "application/x-cbz",
            "application/x-cbr",
            "application/x-cbt",
        ] {
            assert!(text.contains(kind), "{kind}");
        }
    }
}
