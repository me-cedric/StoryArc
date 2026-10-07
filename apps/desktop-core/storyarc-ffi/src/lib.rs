//! C ABI over `storyarc-core`. The header is `include/storyarc_ffi.h`. Keep both in step.

use std::ffi::{CString, c_char};
use std::sync::OnceLock;

/// Returns the core version as a static NUL-terminated string. The caller never frees it.
#[unsafe(no_mangle)]
pub extern "C" fn storyarc_core_version() -> *const c_char {
    static VERSION: OnceLock<CString> = OnceLock::new();
    VERSION
        .get_or_init(|| CString::new(storyarc_core::version()).expect("version has no NUL byte"))
        .as_ptr()
}

#[cfg(test)]
mod tests {
    use std::ffi::CStr;

    #[test]
    fn version_matches_the_core_and_is_stable() {
        let first = super::storyarc_core_version();
        let text = unsafe { CStr::from_ptr(first) }.to_str().expect("utf-8");
        assert_eq!(text, storyarc_core::version());
        assert_eq!(
            first,
            super::storyarc_core_version(),
            "the pointer must stay the same"
        );
    }
}
