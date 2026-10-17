//! What the network sources, the vault and the metered flag need from the core, built once
//! on a worker so the window never waits for a keyring daemon that answers slowly (task
//! 3.17 and 3.18). The core's calls are synchronous: they are made from a worker thread,
//! never from the interface thread and never from inside the runtime.

use std::sync::{Arc, OnceLock};

use gtk::{gio, glib};
use storyarc_core::downloads::policy::NetworkState;
use storyarc_core::metered::{self, MeteredProvider};
use storyarc_core::net::{HttpClient, TrustStore};
use storyarc_core::paths::StorageLocations;
use storyarc_core::runtime::Runtime;
use storyarc_core::secrets::{self, Vault};

use crate::session::LOG_DOMAIN;

pub struct Services {
    pub runtime: Runtime,
    pub http: HttpClient,
    pub trust: TrustStore,
    pub vault: Vault,
    pub provider: Box<dyn MeteredProvider>,
    pub locations: StorageLocations,
}

impl Services {
    fn build() -> Result<Self, String> {
        let runtime = Runtime::new().map_err(|error| error.to_string())?;
        let trust = TrustStore::new();
        let http = HttpClient::new(&runtime, trust.clone()).map_err(|error| error.to_string())?;
        let vault = Vault::new(secrets::system_store(&runtime));
        let provider = metered::system_provider(&runtime);
        Ok(Self {
            runtime,
            http,
            trust,
            vault,
            provider,
            locations: StorageLocations::current(),
        })
    }

    pub fn network(&self) -> NetworkState {
        self.provider.network()
    }

    pub fn is_flatpak(&self) -> bool {
        self.locations.is_flatpak()
    }
}

/// The services, once the worker built them.
#[derive(Default, Clone)]
pub struct Handle(Arc<OnceLock<Arc<Services>>>);

impl Handle {
    pub fn get(&self) -> Option<Arc<Services>> {
        self.0.get().cloned()
    }

    /// Builds the services on a worker and calls `ready` on the interface thread.
    pub fn start(&self, ready: impl FnOnce() + 'static) {
        let slot = self.0.clone();
        glib::spawn_future_local(async move {
            let built = gio::spawn_blocking(Services::build).await;
            match built {
                Ok(Ok(services)) => {
                    let _ = slot.set(Arc::new(services));
                }
                Ok(Err(error)) => glib::g_warning!(LOG_DOMAIN, "No network services: {error}"),
                Err(_) => glib::g_warning!(LOG_DOMAIN, "The network services did not start"),
            }
            ready();
        });
    }
}
