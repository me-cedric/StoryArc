//! Windows: the Internet connection profile's cost (`NetworkCostType`) and the data saver's
//! background restriction, read through WinRT. No profile, or one without Internet access, is
//! no connection. Compiled only on Windows; the `desktop-windows` workflow builds it.

use windows::Networking::Connectivity::{NetworkConnectivityLevel, NetworkInformation};

use super::{MeteredProvider, NetworkState, windows_cost_metered};

pub(super) struct CostProvider;

impl MeteredProvider for CostProvider {
    fn network(&self) -> NetworkState {
        let Ok(profile) = NetworkInformation::GetInternetConnectionProfile() else {
            return NetworkState::Offline;
        };
        let level = profile
            .GetNetworkConnectivityLevel()
            .unwrap_or(NetworkConnectivityLevel::None);
        if level == NetworkConnectivityLevel::None || level == NetworkConnectivityLevel::LocalAccess
        {
            return NetworkState::Offline;
        }
        let Ok(cost) = profile.GetConnectionCost() else {
            return NetworkState::Unmetered;
        };
        let kind = cost.NetworkCostType().map(|k| k.0).unwrap_or(0);
        let restricted = cost.BackgroundDataUsageRestricted().unwrap_or(false);
        if windows_cost_metered(kind, restricted) {
            NetworkState::Metered
        } else {
            NetworkState::Unmetered
        }
    }
}
