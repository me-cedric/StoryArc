//! The settings portal's accent colour, for the chrome accent's System choice.
//!
//! `AdwStyleManager::accent_color` arrived in libadwaita 1.6 and the floor is 1.5, so
//! the crate feature that exposes it is never enabled. The portal key it reads,
//! `org.freedesktop.appearance` `accent-color`, is read here directly over D-Bus and
//! watched for changes, which is the same source and needs nothing above the floor.
//! No portal, no key, or no session bus means no system accent: the choice is absent
//! and the brand colour stays, silently.

use adw::prelude::*;
use gtk::{gio, glib};

use crate::settings::Rgb;

const PORTAL_NAME: &str = "org.freedesktop.portal.Desktop";
const PORTAL_PATH: &str = "/org/freedesktop/portal/desktop";
const SETTINGS_INTERFACE: &str = "org.freedesktop.portal.Settings";
const NAMESPACE: &str = "org.freedesktop.appearance";
const KEY: &str = "accent-color";
const TIMEOUT_MS: i32 = 2000;

/// The accent a portal answer carries: a `(ddd)` triple, possibly wrapped in one or
/// two variants as `Read` returns it. A negative channel means "no accent set".
pub fn accent_from_variant(value: &glib::Variant) -> Option<Rgb> {
    let mut inner = value.clone();
    for _ in 0..6 {
        if let Some((r, g, b)) = inner.get::<(f64, f64, f64)>() {
            return Rgb::from_unit(r, g, b);
        }
        inner = if inner.type_().is_variant() {
            inner.as_variant()?
        } else if inner.type_().is_tuple() && inner.n_children() == 1 {
            inner.child_value(0)
        } else {
            return None;
        };
    }
    None
}

/// Reads the accent once and then on every change, calling `on_accent` on the main
/// loop each time. The proxy is kept alive by the handler. Nothing is reported when
/// the portal is absent.
pub fn watch_accent(on_accent: impl Fn(Option<Rgb>) + 'static) {
    glib::spawn_future_local(async move {
        let proxy = gio::DBusProxy::for_bus_future(
            gio::BusType::Session,
            gio::DBusProxyFlags::DO_NOT_AUTO_START | gio::DBusProxyFlags::DO_NOT_LOAD_PROPERTIES,
            None,
            PORTAL_NAME,
            PORTAL_PATH,
            SETTINGS_INTERFACE,
        )
        .await;
        let Ok(proxy) = proxy else {
            return;
        };
        let read = proxy
            .call_future(
                "Read",
                Some(&(NAMESPACE, KEY).to_variant()),
                gio::DBusCallFlags::NONE,
                TIMEOUT_MS,
            )
            .await;
        let accent = read.ok().as_ref().and_then(accent_from_variant);
        on_accent(accent);
        proxy.connect_local("g-signal", false, move |values| {
            let signal = values.get(2).and_then(|v| v.get::<String>().ok());
            let parameters = values.get(3).and_then(|v| v.get::<glib::Variant>().ok());
            if signal.as_deref() == Some("SettingChanged")
                && let Some(parameters) = parameters
                && parameters.n_children() == 3
                && parameters.child_value(0).get::<String>().as_deref() == Some(NAMESPACE)
                && parameters.child_value(1).get::<String>().as_deref() == Some(KEY)
            {
                on_accent(accent_from_variant(&parameters.child_value(2)));
            }
            None
        });
        // The proxy lives as long as the handler it carries: keep it in the loop.
        std::mem::forget(proxy);
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_portal_answer_unwraps_to_the_accent_however_it_is_boxed() {
        let triple = (0.2f64, 0.4f64, 1.0f64).to_variant();
        assert_eq!(
            accent_from_variant(&triple),
            Some(Rgb {
                r: 51,
                g: 102,
                b: 255
            })
        );
        let boxed = glib::Variant::from_variant(&triple);
        assert_eq!(
            accent_from_variant(&boxed),
            Some(Rgb {
                r: 51,
                g: 102,
                b: 255
            })
        );
        let read_reply = glib::Variant::tuple_from_iter([glib::Variant::from_variant(&boxed)]);
        assert_eq!(
            accent_from_variant(&read_reply),
            Some(Rgb {
                r: 51,
                g: 102,
                b: 255
            })
        );
    }

    #[test]
    fn no_accent_set_or_a_wrong_shape_means_none() {
        assert_eq!(
            accent_from_variant(&(-1.0f64, 0.0f64, 0.0f64).to_variant()),
            None
        );
        assert_eq!(accent_from_variant(&"blue".to_variant()), None);
        assert_eq!(accent_from_variant(&(1u32, 2u32).to_variant()), None);
    }
}
