//! Which way a publication reads. Mirrored from `ReadingPreferences.swift`.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReadingDirection {
    LeftToRight,
    RightToLeft,
}

impl ReadingDirection {
    /// `publication-formats`: an explicit declaration wins; otherwise Japanese with no
    /// declared direction opens right-to-left.
    pub fn inferred(declared: Option<Self>, language_code: Option<&str>) -> Self {
        if let Some(declared) = declared {
            return declared;
        }
        let is_japanese = language_code.is_some_and(|code| code.to_lowercase().starts_with("ja"));
        if is_japanese {
            Self::RightToLeft
        } else {
            Self::LeftToRight
        }
    }

    /// The manifest's spelling of each case, so a fixture's expectation reads as a name.
    pub fn manifest_name(self) -> &'static str {
        match self {
            Self::LeftToRight => "leftToRight",
            Self::RightToLeft => "rightToLeft",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_declaration_wins_over_the_language() {
        assert_eq!(
            ReadingDirection::inferred(Some(ReadingDirection::LeftToRight), Some("ja")),
            ReadingDirection::LeftToRight
        );
    }

    #[test]
    fn japanese_with_no_declaration_opens_right_to_left() {
        assert_eq!(
            ReadingDirection::inferred(None, Some("ja-JP")),
            ReadingDirection::RightToLeft
        );
        assert_eq!(
            ReadingDirection::inferred(None, Some("en")),
            ReadingDirection::LeftToRight
        );
        assert_eq!(
            ReadingDirection::inferred(None, None),
            ReadingDirection::LeftToRight
        );
    }
}
