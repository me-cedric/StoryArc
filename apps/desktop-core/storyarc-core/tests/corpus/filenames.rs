//! What a filename must be read as. Grows with the metadata of task 1.6.

use super::manifest::FilenameCase;

pub fn check(case: &FilenameCase) -> Result<(), String> {
    Err(format!(
        "nothing infers metadata from {:?} yet ({})",
        case.filename, case.why
    ))
}
