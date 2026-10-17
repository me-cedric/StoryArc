//! The notice that names what a scan could not open (`library-browsing`, What could not
//! be opened). It sits above the shelf in an `AdwBanner`, never over a cover, and it is
//! not on a timer: it stays until the reader dismisses it. One file is named with its
//! own reason; several are counted, and the notice leads to a list naming each with its
//! reason. Dismissing it keeps the list reachable from the library, and the count does
//! not come back for the same files unless the set changes.

use std::collections::BTreeSet;

use crate::strings::{tr, tr_args};

/// One file a scan could not open: its name and the reason in the words
/// `publication-formats` gives.
pub type Skipped = (String, String);

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Notice {
    /// Nothing to say, or the reader dismissed this exact set.
    Hidden,
    /// One file, named, with its reason.
    One { name: String, reason: String },
    /// Several, counted; the button leads to the list.
    Several(usize),
}

impl Notice {
    /// The notice for the files skipped now, given the set the reader dismissed last.
    pub fn of(skipped: &[Skipped], dismissed: &BTreeSet<Skipped>) -> Self {
        let now: BTreeSet<Skipped> = skipped.iter().cloned().collect();
        if now.is_empty() || &now == dismissed {
            return Self::Hidden;
        }
        match skipped {
            [(name, reason)] => Self::One {
                name: name.clone(),
                reason: reason.clone(),
            },
            _ => Self::Several(now.len()),
        }
    }

    /// The banner's line.
    pub fn title(&self) -> Option<String> {
        match self {
            Self::Hidden => None,
            Self::One { name, reason } => Some(format!(
                "{}: {reason}",
                tr_args("library.skipped.one %s", "“%s” couldn’t be opened", &[name])
            )),
            Self::Several(count) => Some(tr_args(
                "library.skipped %d",
                "%d couldn’t be opened",
                &[count],
            )),
        }
    }

    /// The banner's one button: the list for several, a dismissal for one.
    pub fn button(&self) -> Option<String> {
        match self {
            Self::Hidden => None,
            Self::One { .. } => Some(tr("library.skipped.dismiss", "Dismiss")),
            Self::Several(_) => Some(tr("library.skipped.show", "Show")),
        }
    }
}

/// The set a dismissal remembers: the files skipped when the reader dismissed it.
pub fn dismissed(skipped: &[Skipped]) -> BTreeSet<Skipped> {
    skipped.iter().cloned().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file(name: &str, reason: &str) -> Skipped {
        (name.into(), reason.into())
    }

    #[test]
    fn one_file_is_named_with_its_own_reason() {
        let skipped = [file("refused.cb7", "CB7 is not supported")];
        let notice = Notice::of(&skipped, &BTreeSet::new());
        assert_eq!(
            notice.title().as_deref(),
            Some("“refused.cb7” couldn’t be opened: CB7 is not supported")
        );
        assert_eq!(notice.button().as_deref(), Some("Dismiss"));
    }

    #[test]
    fn several_are_counted_and_lead_to_the_list() {
        let skipped = [
            file("a.cb7", "CB7 is not supported"),
            file("b.cbr", "the archive is password protected"),
        ];
        let notice = Notice::of(&skipped, &BTreeSet::new());
        assert_eq!(notice, Notice::Several(2));
        assert_eq!(notice.title().as_deref(), Some("2 couldn’t be opened"));
        assert_eq!(notice.button().as_deref(), Some("Show"));
    }

    #[test]
    fn a_dismissed_set_stays_dismissed_until_it_changes() {
        let skipped = vec![file("a.cb7", "CB7 is not supported")];
        let gone = dismissed(&skipped);
        assert_eq!(Notice::of(&skipped, &gone), Notice::Hidden);
        let mut more = skipped.clone();
        more.push(file("b.cbr", "the archive cannot be read"));
        assert_eq!(Notice::of(&more, &gone), Notice::Several(2));
        assert_eq!(Notice::of(&[], &BTreeSet::new()), Notice::Hidden);
    }
}
