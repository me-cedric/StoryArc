//! Moments as the records write them: seconds since the Unix epoch in memory, and the
//! `2025-12-30T13:06:40Z` form of the library documents on the wire.
//!
//! Hand-written rather than a calendar crate: the two mobile encoders write exactly this
//! shape (`JSONEncoder.dateEncodingStrategy = .iso8601` and `kotlinx.datetime.Instant`),
//! which is whole seconds in UTC and nothing else, and reading it back is forty lines.

use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// A moment in whole seconds since 1970-01-01T00:00:00Z.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub struct Timestamp(pub i64);

impl Timestamp {
    /// The clock now, in whole seconds.
    pub fn now() -> Self {
        let seconds = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_secs() as i64)
            .unwrap_or_default();
        Self(seconds)
    }

    /// The moment the filesystem reports for a file, in whole seconds.
    pub fn from_system_time(time: std::time::SystemTime) -> Self {
        match time.duration_since(std::time::UNIX_EPOCH) {
            Ok(elapsed) => Self(elapsed.as_secs() as i64),
            Err(before) => Self(-(before.duration().as_secs() as i64)),
        }
    }

    /// `2025-12-30T13:06:40Z`.
    pub fn to_rfc3339(self) -> String {
        let (year, month, day) = civil_from_days(self.0.div_euclid(86_400));
        let seconds = self.0.rem_euclid(86_400);
        format!(
            "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
            seconds / 3600,
            (seconds / 60) % 60,
            seconds % 60
        )
    }

    /// Reads the form above, with or without fractional seconds, in UTC only. `None` for
    /// anything else, because a lenient reader of a date is how two records disagree
    /// about when something happened.
    pub fn parse_rfc3339(text: &str) -> Option<Self> {
        let text = text.strip_suffix('Z')?;
        let (date, time) = text.split_once('T')?;
        let mut date_parts = date.split('-');
        let year: i64 = date_parts.next()?.parse().ok()?;
        let month: u32 = date_parts.next()?.parse().ok()?;
        let day: u32 = date_parts.next()?.parse().ok()?;
        if date_parts.next().is_some() || !(1..=12).contains(&month) || !(1..=31).contains(&day) {
            return None;
        }
        let time = time.split('.').next()?;
        let mut time_parts = time.split(':');
        let hour: i64 = time_parts.next()?.parse().ok()?;
        let minute: i64 = time_parts.next()?.parse().ok()?;
        let second: i64 = time_parts.next()?.parse().ok()?;
        if time_parts.next().is_some() || hour > 23 || minute > 59 || second > 60 {
            return None;
        }
        let days = days_from_civil(year, month, day);
        Some(Self(days * 86_400 + hour * 3600 + minute * 60 + second))
    }

    /// Midnight UTC on a calendar date, for a publication's release date.
    pub fn from_civil(year: i64, month: u32, day: u32) -> Self {
        Self(days_from_civil(year, month, day) * 86_400)
    }

    /// The first instant of the month this moment falls in, in UTC.
    pub fn start_of_month(self) -> Self {
        let (year, month, _) = civil_from_days(self.0.div_euclid(86_400));
        Self::from_civil(year, month, 1)
    }

    /// The calendar date, in UTC.
    pub fn civil(self) -> (i64, u32, u32) {
        civil_from_days(self.0.div_euclid(86_400))
    }
}

impl Serialize for Timestamp {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.to_rfc3339())
    }
}

impl<'de> Deserialize<'de> for Timestamp {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let text = String::deserialize(deserializer)?;
        Self::parse_rfc3339(&text)
            .ok_or_else(|| serde::de::Error::custom(format!("not an RFC 3339 UTC moment: {text}")))
    }
}

/// Days since the epoch to a proleptic Gregorian date (Howard Hinnant's algorithm).
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if month <= 2 { year + 1 } else { year }, month, day)
}

/// A proleptic Gregorian date to days since the epoch.
fn days_from_civil(year: i64, month: u32, day: u32) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let yoe = year.rem_euclid(400);
    let month = i64::from(month);
    let mp = if month > 2 { month - 3 } else { month + 9 };
    let doy = (153 * mp + 2) / 5 + i64::from(day) - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_fixture_moments_round_trip() {
        for text in [
            "2025-12-30T13:06:40Z",
            "2026-01-01T00:04:05Z",
            "1970-01-01T00:00:00Z",
            "2000-02-29T23:59:59Z",
        ] {
            let moment = Timestamp::parse_rfc3339(text).expect(text);
            assert_eq!(moment.to_rfc3339(), text);
        }
        assert_eq!(
            Timestamp::parse_rfc3339("2025-12-30T13:06:40Z"),
            Some(Timestamp(1_767_100_000))
        );
    }

    #[test]
    fn a_fractional_second_is_read_and_an_offset_is_refused() {
        assert_eq!(
            Timestamp::parse_rfc3339("2025-12-30T13:06:40.250Z"),
            Some(Timestamp(1_767_100_000))
        );
        assert_eq!(Timestamp::parse_rfc3339("2025-12-30T13:06:40+01:00"), None);
        assert_eq!(Timestamp::parse_rfc3339("yesterday"), None);
    }

    #[test]
    fn a_moment_before_the_epoch_formats() {
        assert_eq!(Timestamp(-1).to_rfc3339(), "1969-12-31T23:59:59Z");
    }

    #[test]
    fn the_start_of_a_month_is_its_first_midnight() {
        let moment = Timestamp::parse_rfc3339("2026-03-28T09:00:00Z").unwrap();
        assert_eq!(moment.start_of_month().to_rfc3339(), "2026-03-01T00:00:00Z");
    }
}
