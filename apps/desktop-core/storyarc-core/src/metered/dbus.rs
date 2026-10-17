//! Linux: the network-monitor portal first, which answers inside a Flatpak and on any desktop
//! with `xdg-desktop-portal`, then NetworkManager's `Metered` and `State` on the system bus. A
//! system with neither says nothing, and an undescribed connection is unmetered. Each reading
//! is bounded to two seconds so a stuck bus never holds the queue. Compiled only on Linux.

use std::time::Duration;

use zbus::Connection;
use zbus::zvariant::OwnedValue;

use super::{MeteredProvider, NetworkState, network_manager_metered};
use crate::runtime::Runtime;

const LIMIT: Duration = Duration::from_secs(2);
/// `NM_STATE_CONNECTED_GLOBAL`; anything below it has no route to the Internet.
const NM_CONNECTED_GLOBAL: u32 = 70;

pub(super) struct DbusProvider {
    runtime: Runtime,
}

impl DbusProvider {
    pub(super) fn new(runtime: &Runtime) -> Self {
        Self {
            runtime: runtime.clone(),
        }
    }
}

async fn portal() -> zbus::Result<NetworkState> {
    let bus = Connection::session().await?;
    let ask = |method: &'static str| {
        let bus = bus.clone();
        async move {
            bus.call_method(
                Some("org.freedesktop.portal.Desktop"),
                "/org/freedesktop/portal/desktop",
                Some("org.freedesktop.portal.NetworkMonitor"),
                method,
                &(),
            )
            .await?
            .body()
            .deserialize::<bool>()
        }
    };
    if !ask("GetAvailable").await? {
        return Ok(NetworkState::Offline);
    }
    Ok(if ask("GetMetered").await? {
        NetworkState::Metered
    } else {
        NetworkState::Unmetered
    })
}

async fn network_manager() -> zbus::Result<NetworkState> {
    let bus = Connection::system().await?;
    let property = |name: &'static str| {
        let bus = bus.clone();
        async move {
            let value = bus
                .call_method(
                    Some("org.freedesktop.NetworkManager"),
                    "/org/freedesktop/NetworkManager",
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &("org.freedesktop.NetworkManager", name),
                )
                .await?
                .body()
                .deserialize::<OwnedValue>()?;
            u32::try_from(value).map_err(zbus::Error::from)
        }
    };
    if property("State").await? < NM_CONNECTED_GLOBAL {
        return Ok(NetworkState::Offline);
    }
    Ok(if network_manager_metered(property("Metered").await?) {
        NetworkState::Metered
    } else {
        NetworkState::Unmetered
    })
}

impl MeteredProvider for DbusProvider {
    fn network(&self) -> NetworkState {
        let reading = self.runtime.block_on_within(LIMIT, async {
            match portal().await {
                Ok(state) => Some(state),
                Err(_) => network_manager().await.ok(),
            }
        });
        reading.flatten().unwrap_or(NetworkState::Unmetered)
    }
}
