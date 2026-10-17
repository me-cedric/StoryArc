//! Whether the connection is metered (`desktop-experience`, *Metered connections*; task 3.9 of
//! `desktop-clients`).
//!
//! A [`MeteredProvider`] asks the system once per call: Windows through `NetworkCostType` and
//! the data-saver flag, Linux through the network-monitor portal and then NetworkManager. A
//! connection the system does not describe is not metered, as the spec requires; the system's
//! data saver makes it metered regardless of the app's own setting (`offline-downloads`,
//! *Data saver*). [`NetworkWatch`] turns readings into changes, which the app feeds to
//! [`crate::downloads::queue::DownloadQueue::holding`] so a download the policy holds back
//! pauses mid-transfer and resumes when an unmetered connection returns.

#[cfg(windows)]
mod cost;
#[cfg(target_os = "linux")]
mod dbus;

use std::sync::Mutex;

pub use crate::downloads::policy::NetworkState;
use crate::runtime::Runtime;

/// Reads the connection's state from the system.
pub trait MeteredProvider: Send + Sync {
    fn network(&self) -> NetworkState;
}

/// A provider a test sets by hand.
#[derive(Debug)]
pub struct FakeMetered {
    state: Mutex<NetworkState>,
}

impl FakeMetered {
    pub fn new(state: NetworkState) -> Self {
        Self {
            state: Mutex::new(state),
        }
    }

    pub fn set(&self, state: NetworkState) {
        *self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = state;
    }
}

impl MeteredProvider for FakeMetered {
    fn network(&self) -> NetworkState {
        *self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

/// A system that says nothing: every connection is unmetered.
#[derive(Debug, Default)]
pub struct Undescribed;

impl MeteredProvider for Undescribed {
    fn network(&self) -> NetworkState {
        NetworkState::Unmetered
    }
}

/// The system's own provider: `NetworkCostType` on Windows, the portal or NetworkManager on
/// Linux, and [`Undescribed`] elsewhere.
pub fn system_provider(runtime: &Runtime) -> Box<dyn MeteredProvider> {
    #[cfg(windows)]
    {
        let _ = runtime;
        Box::new(cost::CostProvider)
    }
    #[cfg(target_os = "linux")]
    {
        Box::new(dbus::DbusProvider::new(runtime))
    }
    #[cfg(not(any(windows, target_os = "linux")))]
    {
        let _ = runtime;
        Box::new(Undescribed)
    }
}

/// What NetworkManager's `Metered` property says, as the `NMMetered` values: 0 unknown,
/// 1 yes, 2 no, 3 guessed yes, 4 guessed no. Unknown is not metered.
pub fn network_manager_metered(value: u32) -> bool {
    matches!(value, 1 | 3)
}

/// What Windows' `NetworkCostType` says (0 unknown, 1 unrestricted, 2 fixed, 3 variable),
/// with the data saver's background restriction. Unknown is not metered; a capped plan, a
/// per-byte plan or the data saver is.
pub fn windows_cost_metered(cost_type: i32, background_restricted: bool) -> bool {
    background_restricted || matches!(cost_type, 2 | 3)
}

/// Turns readings into changes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NetworkWatch {
    last: NetworkState,
}

impl NetworkWatch {
    pub fn new(provider: &dyn MeteredProvider) -> Self {
        Self {
            last: provider.network(),
        }
    }

    pub fn current(&self) -> NetworkState {
        self.last
    }

    /// The new state when it differs from the last reading.
    pub fn poll(&mut self, provider: &dyn MeteredProvider) -> Option<NetworkState> {
        let now = provider.network();
        (now != self.last).then(|| {
            self.last = now;
            now
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::downloads::policy::DownloadPolicy;
    use crate::downloads::queue::{Download, DownloadQueue, DownloadState, Pause};

    #[test]
    fn the_systems_words_map_to_metered_and_unknown_is_not() {
        assert!(!network_manager_metered(0));
        assert!(network_manager_metered(1));
        assert!(!network_manager_metered(2));
        assert!(network_manager_metered(3));
        assert!(!network_manager_metered(4));
        assert!(!windows_cost_metered(0, false));
        assert!(!windows_cost_metered(1, false));
        assert!(windows_cost_metered(2, false));
        assert!(windows_cost_metered(3, false));
        assert!(windows_cost_metered(1, true), "the data saver is metered");
        assert_eq!(Undescribed.network(), NetworkState::Unmetered);
    }

    #[test]
    fn a_change_to_metered_mid_download_pauses_what_the_policy_holds_back_and_back_resumes_it() {
        let provider = FakeMetered::new(NetworkState::Unmetered);
        let mut watch = NetworkWatch::new(&provider);
        let policy = DownloadPolicy::default();
        let queue = DownloadQueue::default()
            .queueing(Download::new("a", "A", "x"))
            .queueing(Download::new("b", "B", "x").by_hand())
            .marking("a", DownloadState::Running)
            .marking("b", DownloadState::Running);
        assert_eq!(watch.poll(&provider), None);

        provider.set(NetworkState::Metered);
        let changed = watch.poll(&provider).unwrap();
        assert_eq!(changed, NetworkState::Metered);
        let held = queue.holding(changed, &policy, 0);
        assert_eq!(
            held.get("a").unwrap().state,
            DownloadState::Paused(Pause::WaitingForUnmetered)
        );
        assert_eq!(held.get("b").unwrap().state, DownloadState::Running);

        provider.set(NetworkState::Unmetered);
        let back = held.holding(watch.poll(&provider).unwrap(), &policy, 0);
        assert_eq!(back.get("a").unwrap().state, DownloadState::Queued);
        assert_eq!(back.startable(NetworkState::Unmetered, &policy), ["a"]);

        provider.set(NetworkState::Offline);
        let away = back.holding(watch.poll(&provider).unwrap(), &policy, 0);
        assert_eq!(
            away.get("a").unwrap().state,
            DownloadState::Paused(Pause::WaitingForNetwork)
        );
    }
}
