//! Which download may run now (`offline-downloads`, *Network policy* and *Concurrency*;
//! `desktop-experience`, *Metered connections*).
//!
//! Pure: the network state comes from the metered flag provider ([`crate::metered`]), the
//! settings from the app, and the answer is a value a test can assert.

use serde::{Deserialize, Serialize};

/// What the system says about the connection now.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum NetworkState {
    /// Not metered, or the system does not say: "a connection the system does not describe
    /// SHALL be treated as not metered".
    Unmetered,
    /// Metered: a phone tether, a capped plan, Low Data Mode.
    Metered,
    /// No connection at all.
    Offline,
}

/// The reader's settings that decide admission.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DownloadPolicy {
    /// "Download over Wi-Fi only": on a desktop, over an unmetered connection only.
    pub unmetered_only: bool,
    /// How many run at once on an unmetered connection.
    pub concurrency: usize,
    /// How many run at once on a metered one: lower, as the spec asks.
    pub metered_concurrency: usize,
    /// The most the downloads folder may hold, when the reader set a limit.
    pub storage_limit: Option<u64>,
}

impl Default for DownloadPolicy {
    fn default() -> Self {
        Self {
            unmetered_only: true,
            concurrency: 3,
            metered_concurrency: 1,
            storage_limit: None,
        }
    }
}

/// Whether an item may start, and if not, the grey line the queue says.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Admission {
    Run,
    /// Held back on a metered connection until an unmetered one returns.
    WaitForUnmetered,
    /// No connection: the queue waits in grey.
    WaitForNetwork,
    /// The storage limit is reached; the app offers to remove finished publications.
    StorageLimitReached,
}

impl DownloadPolicy {
    /// Whether an item may run on `network`. An item the reader started by hand on a metered
    /// connection runs ("overriding once"); one the policy queued does not.
    pub fn admit(
        &self,
        network: NetworkState,
        started_by_hand: bool,
        used: u64,
        size: Option<u64>,
    ) -> Admission {
        if network == NetworkState::Offline {
            return Admission::WaitForNetwork;
        }
        if let Some(limit) = self.storage_limit
            && used.saturating_add(size.unwrap_or(0)) > limit
        {
            return Admission::StorageLimitReached;
        }
        if network == NetworkState::Metered && self.unmetered_only && !started_by_hand {
            return Admission::WaitForUnmetered;
        }
        Admission::Run
    }

    /// How many may run at once on `network`.
    pub fn concurrency(&self, network: NetworkState) -> usize {
        match network {
            NetworkState::Unmetered => self.concurrency.max(1),
            NetworkState::Metered => self.metered_concurrency.clamp(1, self.concurrency.max(1)),
            NetworkState::Offline => 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_metered_network_holds_back_what_the_policy_queued_and_runs_what_the_reader_asked_for() {
        let policy = DownloadPolicy::default();
        assert_eq!(
            policy.admit(NetworkState::Metered, false, 0, None),
            Admission::WaitForUnmetered
        );
        assert_eq!(
            policy.admit(NetworkState::Metered, true, 0, None),
            Admission::Run
        );
        assert_eq!(
            policy.admit(NetworkState::Unmetered, false, 0, None),
            Admission::Run
        );
    }

    #[test]
    fn with_the_setting_off_a_metered_network_runs_everything() {
        let policy = DownloadPolicy {
            unmetered_only: false,
            ..DownloadPolicy::default()
        };
        assert_eq!(
            policy.admit(NetworkState::Metered, false, 0, None),
            Admission::Run
        );
    }

    #[test]
    fn no_connection_waits_and_runs_nothing() {
        let policy = DownloadPolicy::default();
        assert_eq!(
            policy.admit(NetworkState::Offline, true, 0, None),
            Admission::WaitForNetwork
        );
        assert_eq!(policy.concurrency(NetworkState::Offline), 0);
    }

    #[test]
    fn the_bound_is_lowered_on_a_metered_connection() {
        let policy = DownloadPolicy::default();
        assert_eq!(policy.concurrency(NetworkState::Unmetered), 3);
        assert_eq!(policy.concurrency(NetworkState::Metered), 1);
    }

    #[test]
    fn a_storage_limit_stops_what_would_cross_it() {
        let policy = DownloadPolicy {
            storage_limit: Some(1_000),
            ..DownloadPolicy::default()
        };
        assert_eq!(
            policy.admit(NetworkState::Unmetered, true, 900, Some(200)),
            Admission::StorageLimitReached
        );
        assert_eq!(
            policy.admit(NetworkState::Unmetered, true, 900, Some(100)),
            Admission::Run
        );
    }
}
