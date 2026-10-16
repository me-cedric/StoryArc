//! What a filename must be read as (task 1.6). The twin of iOS's `FilenameMetadataTests`.

use storyarc_core::formats::FilenameMetadata;

use super::comics::expect;
use super::manifest::FilenameCase;

pub fn check(case: &FilenameCase) -> Result<(), String> {
    let meta = FilenameMetadata::new(&case.filename, None, None);
    let why = &case.why;
    expect(
        &format!("series ({why})"),
        meta.series.clone(),
        case.series.clone(),
    )?;
    expect(
        &format!("number ({why})"),
        meta.number.clone(),
        case.number.clone(),
    )?;
    expect(&format!("volume ({why})"), meta.volume, case.volume)?;
    expect(&format!("year ({why})"), meta.year, case.year)?;
    // Every value inferred from a filename is marked inferred, so an authoritative source
    // can replace it later without a conflict prompt.
    expect("inferred", meta.is_inferred, true)
}
