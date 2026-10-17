//! A publication as a library cell shows it, with the fields the shared fixtures name.
//! Built from the core's record by `adapter.rs`.

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Format {
    Cbz,
    Cbr,
    Cbt,
    Cb7,
    Epub,
    Pdf,
    Folder,
    Audiobook,
}

impl Format {
    pub const ALL: [Self; 8] = [
        Self::Cbz,
        Self::Cbr,
        Self::Cbt,
        Self::Cb7,
        Self::Epub,
        Self::Pdf,
        Self::Folder,
        Self::Audiobook,
    ];

    /// The name the format filter shows.
    pub fn display_name(self) -> &'static str {
        match self {
            Self::Cbz => "CBZ",
            Self::Cbr => "CBR",
            Self::Cbt => "CBT",
            Self::Cb7 => "CB7",
            Self::Epub => "EPUB",
            Self::Pdf => "PDF",
            Self::Folder => "Image Folder",
            Self::Audiobook => "Audiobook",
        }
    }
}

/// The reading position, in the shape of the portability document's `progress` record.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Progress {
    Unread,
    Reading { index: u32, of: u32 },
    Finished,
}

impl Progress {
    /// The percent the cell's rail shows. Finished is full.
    pub fn percent(self) -> u32 {
        match self {
            Self::Unread => 0,
            Self::Reading { index, of } if of > 0 => {
                (u64::from(index) * 100 / u64::from(of)) as u32
            }
            Self::Reading { .. } => 0,
            Self::Finished => 100,
        }
    }
}

/// Where a cell is on the cover ladder: a placeholder until the thumbnail decodes, the
/// full cover once it has. A decode never blocks a scroll, so every step is a state.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Cover {
    #[default]
    Placeholder,
    Thumbnail,
    Full,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LibraryEntry {
    /// The identity the window model and the progress store key on.
    pub id: String,
    pub title: String,
    pub series: Option<String>,
    pub issue: Option<u32>,
    pub author: Option<String>,
    pub format: Format,
    /// The source the publication came from, by name.
    pub source: String,
    pub page_count: u32,
    pub progress: Progress,
    pub downloaded: bool,
    /// Seconds, for the Recently Added sort.
    pub added_at: u64,
    /// Seconds, for Continue reading and the Last Read sort.
    pub last_read_at: Option<u64>,
    pub cover: Cover,
    /// The named reason the file could not be opened, as a string key, when it could not.
    pub cannot_open: Option<String>,
}

impl LibraryEntry {
    /// What the cell says under the cover: the reason it cannot open, else the title.
    pub fn cell_label_key(&self) -> Option<&str> {
        self.cannot_open.as_deref()
    }

    /// What a screen reader announces for the cell: title, series and issue, progress,
    /// downloaded, and the reason when it cannot open.
    pub fn accessible_description(&self) -> String {
        let mut parts = vec![self.title.clone()];
        if let Some(series) = &self.series {
            match self.issue {
                Some(issue) => parts.push(format!("{series} {issue}")),
                None => parts.push(series.clone()),
            }
        }
        match self.progress {
            Progress::Unread => {}
            Progress::Reading { .. } => parts.push(format!("{}% read", self.progress.percent())),
            Progress::Finished => parts.push("finished".into()),
        }
        if self.downloaded {
            parts.push("downloaded".into());
        }
        if self.cannot_open.is_some() {
            parts.push("cannot be opened".into());
        }
        parts.join(", ")
    }
}
