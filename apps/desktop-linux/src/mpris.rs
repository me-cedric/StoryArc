//! MPRIS, the desktop's own media controls (task 4.13; `desktop-experience`, Media keys
//! and system media controls). The two interfaces of `org.mpris.MediaPlayer2` are served
//! over GDBus, which GTK already carries, so no crate is added. The desktop routes the
//! keyboard's media keys to the player it chose, which is how the app never fights for
//! them: it grabs no key, it owns a bus name while something plays and lets it go when
//! playback ends, so the entry leaves the controls (the spec's The system overlay).
//!
//! The metadata and the property payloads are pure and test on any host; the bus half
//! runs under `scripts/headless-proof.sh` against `playerctl` on a private session bus.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Duration;

use gtk::gio;
use gtk::glib::{self, prelude::*};

use crate::audio::PlayState;

pub const BUS_NAME: &str = "org.mpris.MediaPlayer2.storyarc";
pub const OBJECT_PATH: &str = "/org/mpris/MediaPlayer2";
const ROOT_IFACE: &str = "org.mpris.MediaPlayer2";
const PLAYER_IFACE: &str = "org.mpris.MediaPlayer2.Player";

const INTROSPECTION: &str = r#"<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition"><arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/></method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>"#;

/// What the controls show: the publication's title, its author, its cover and how long it is.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct NowPlaying {
    pub title: String,
    pub author: Option<String>,
    pub cover: Option<PathBuf>,
    pub length: Option<Duration>,
    /// A number that changes when the chapter does, so the controls redraw.
    pub track: u64,
}

impl NowPlaying {
    pub fn track_id(&self) -> String {
        format!("/com/mecedric/StoryArc/track/{}", self.track)
    }

    /// The MPRIS metadata map: `mpris:trackid`, `mpris:length`, `mpris:artUrl`,
    /// `xesam:title`, `xesam:artist`. A field the publication lacks is absent, not blank.
    pub fn metadata(&self) -> glib::Variant {
        let dict = glib::VariantDict::new(None);
        if let Ok(path) = glib::variant::ObjectPath::try_from(self.track_id()) {
            dict.insert_value("mpris:trackid", &path.to_variant());
        }
        dict.insert_value("xesam:title", &self.title.to_variant());
        if let Some(author) = &self.author {
            dict.insert_value("xesam:artist", &vec![author.clone()].to_variant());
        }
        if let Some(cover) = &self.cover {
            dict.insert_value("mpris:artUrl", &art_url(cover).to_variant());
        }
        if let Some(length) = self.length {
            dict.insert_value("mpris:length", &micros(length).to_variant());
        }
        dict.end()
    }
}

fn art_url(cover: &Path) -> String {
    glib::filename_to_uri(cover, None)
        .map(|uri| uri.to_string())
        .unwrap_or_else(|_| format!("file://{}", cover.display()))
}

fn micros(duration: Duration) -> i64 {
    i64::try_from(duration.as_micros()).unwrap_or(i64::MAX)
}

/// What the controls or a media key asked for.
#[derive(Clone, Debug, PartialEq)]
pub enum Command {
    PlayPause,
    Play,
    Pause,
    Stop,
    Next,
    Previous,
    /// Relative, in microseconds, as MPRIS sends it.
    Seek(i64),
    SetPosition(Duration),
    SetRate(f64),
    Raise,
}

/// The player as the bus sees it.
#[derive(Clone, Debug, PartialEq)]
pub struct Shown {
    pub status: PlayState,
    pub position: Duration,
    pub rate: f64,
    pub now: NowPlaying,
    pub can_go_next: bool,
    pub can_go_previous: bool,
}

impl Default for Shown {
    fn default() -> Self {
        Self {
            status: PlayState::Stopped,
            position: Duration::ZERO,
            rate: 1.0,
            now: NowPlaying::default(),
            can_go_next: false,
            can_go_previous: false,
        }
    }
}

impl Shown {
    /// One property's value, by its name on the player interface.
    pub fn player_property(&self, name: &str) -> Option<glib::Variant> {
        Some(match name {
            "PlaybackStatus" => self.status.mpris().to_variant(),
            "Rate" => self.rate.to_variant(),
            "Metadata" => self.now.metadata(),
            "Volume" => 1.0f64.to_variant(),
            "Position" => micros(self.position).to_variant(),
            "MinimumRate" => 0.5f64.to_variant(),
            "MaximumRate" => 3.0f64.to_variant(),
            "CanGoNext" => self.can_go_next.to_variant(),
            "CanGoPrevious" => self.can_go_previous.to_variant(),
            "CanPlay" | "CanPause" | "CanSeek" | "CanControl" => true.to_variant(),
            _ => return None,
        })
    }

    /// The `PropertiesChanged` payload for the properties that differ from `before`.
    pub fn changed_since(&self, before: &Self) -> Option<glib::Variant> {
        let dict = glib::VariantDict::new(None);
        let mut any = false;
        for name in [
            "PlaybackStatus",
            "Rate",
            "Metadata",
            "CanGoNext",
            "CanGoPrevious",
        ] {
            let (now, then) = (self.player_property(name), before.player_property(name));
            if now != then
                && let Some(value) = now
            {
                dict.insert_value(name, &value);
                any = true;
            }
        }
        any.then(|| {
            glib::Variant::tuple_from_iter([
                PLAYER_IFACE.to_variant(),
                dict.end(),
                Vec::<String>::new().to_variant(),
            ])
        })
    }
}

/// One property's value on the root interface.
pub fn root_property(name: &str) -> Option<glib::Variant> {
    Some(match name {
        "CanQuit" | "HasTrackList" => false.to_variant(),
        "CanRaise" => true.to_variant(),
        "Identity" => "StoryArc".to_variant(),
        "DesktopEntry" => crate::APP_ID.to_variant(),
        "SupportedUriSchemes" | "SupportedMimeTypes" => Vec::<String>::new().to_variant(),
        _ => return None,
    })
}

/// The command a method call asks for, or `None` for one the player does not take.
pub fn command_of(method: &str, parameters: &glib::Variant) -> Option<Command> {
    Some(match method {
        "PlayPause" => Command::PlayPause,
        "Play" => Command::Play,
        "Pause" => Command::Pause,
        "Stop" => Command::Stop,
        "Next" => Command::Next,
        "Previous" => Command::Previous,
        "Raise" => Command::Raise,
        "Seek" => Command::Seek(parameters.child_value(0).get::<i64>()?),
        "SetPosition" => {
            let position = parameters.child_value(1).get::<i64>()?;
            Command::SetPosition(Duration::from_micros(u64::try_from(position).ok()?))
        }
        _ => return None,
    })
}

pub struct Mpris {
    connection: gio::DBusConnection,
    shown: RefCell<Shown>,
    owner: RefCell<Option<gio::OwnerId>>,
    registrations: RefCell<Vec<gio::RegistrationId>>,
}

impl Mpris {
    /// Serves the two interfaces on `connection` and owns the name. `on_command` hears
    /// what the controls ask; the player answers it and then calls [`show`](Self::show).
    pub fn publish(
        connection: gio::DBusConnection,
        on_command: impl Fn(Command) + 'static,
    ) -> Result<Rc<Self>, String> {
        let node = gio::DBusNodeInfo::for_xml(INTROSPECTION).map_err(|e| e.to_string())?;
        let mpris = Rc::new(Self {
            connection: connection.clone(),
            shown: RefCell::default(),
            owner: RefCell::default(),
            registrations: RefCell::default(),
        });
        let on_command = Rc::new(on_command);
        for (iface, is_player) in [(ROOT_IFACE, false), (PLAYER_IFACE, true)] {
            let info = node
                .lookup_interface(iface)
                .ok_or_else(|| format!("{iface} missing from the introspection"))?;
            let calls = on_command.clone();
            let weak = Rc::downgrade(&mpris);
            let setter = Rc::downgrade(&mpris);
            let setter_calls = on_command.clone();
            let id = connection
                .register_object(OBJECT_PATH, &info)
                .method_call(move |_, _, _, _, method, parameters, invocation| {
                    match command_of(method, &parameters) {
                        Some(command) => {
                            calls(command);
                            invocation.return_value(None);
                        }
                        None => invocation.return_dbus_error(
                            "org.freedesktop.DBus.Error.NotSupported",
                            "StoryArc does not take this call",
                        ),
                    }
                })
                .property(move |_, _, _, _, name| {
                    let value = if is_player {
                        weak.upgrade()
                            .and_then(|mpris| mpris.shown.borrow().player_property(name))
                    } else {
                        root_property(name)
                    };
                    value.unwrap_or_else(|| "".to_variant())
                })
                .set_property(move |_, _, _, _, name, value| {
                    if name == "Rate"
                        && let Some(rate) = value.get::<f64>()
                    {
                        setter_calls(Command::SetRate(rate));
                        if let Some(mpris) = setter.upgrade() {
                            mpris.shown.borrow_mut().rate = rate;
                        }
                        return true;
                    }
                    name == "Volume"
                })
                .build()
                .map_err(|e| e.to_string())?;
            mpris.registrations.borrow_mut().push(id);
        }
        let owner = gio::bus_own_name_on_connection(
            &connection,
            BUS_NAME,
            gio::BusNameOwnerFlags::NONE,
            |_, _| {},
            |_, _| {},
        );
        *mpris.owner.borrow_mut() = Some(owner);
        Ok(mpris)
    }

    /// Tells the controls what changed, and `Seeked` when the position jumped.
    pub fn show(&self, shown: Shown, seeked: bool) {
        let changed = shown.changed_since(&self.shown.borrow());
        let position = shown.position;
        *self.shown.borrow_mut() = shown;
        if let Some(payload) = changed {
            let _ = self.connection.emit_signal(
                None,
                OBJECT_PATH,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                Some(&payload),
            );
        }
        if seeked {
            let _ = self.connection.emit_signal(
                None,
                OBJECT_PATH,
                PLAYER_IFACE,
                "Seeked",
                Some(&(micros(position),).to_variant()),
            );
        }
    }
}

impl Drop for Mpris {
    /// The entry leaves the controls with the player.
    fn drop(&mut self) {
        if let Some(owner) = self.owner.borrow_mut().take() {
            gio::bus_unown_name(owner);
        }
        for id in self.registrations.borrow_mut().drain(..) {
            let _ = self.connection.unregister_object(id);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::process::Command as Process;
    use std::time::Instant;

    use super::*;

    fn now_playing() -> NowPlaying {
        NowPlaying {
            title: "Natural Sort".into(),
            author: Some("A. Writer".into()),
            cover: Some(PathBuf::from("/tmp/cover.png")),
            length: Some(Duration::from_secs(6)),
            track: 2,
        }
    }

    #[test]
    fn the_metadata_carries_title_cover_length_and_an_object_path_track() {
        let metadata = now_playing().metadata();
        assert_eq!(metadata.type_().as_str(), "a{sv}");
        let dict = glib::VariantDict::new(Some(&metadata));
        assert_eq!(
            dict.lookup::<String>("xesam:title").unwrap(),
            Some("Natural Sort".into())
        );
        assert_eq!(
            dict.lookup::<Vec<String>>("xesam:artist").unwrap(),
            Some(vec!["A. Writer".into()])
        );
        assert_eq!(
            dict.lookup::<String>("mpris:artUrl").unwrap(),
            Some("file:///tmp/cover.png".into())
        );
        assert_eq!(dict.lookup::<i64>("mpris:length").unwrap(), Some(6_000_000));
        assert_eq!(
            dict.lookup_value("mpris:trackid", None)
                .map(|v| v.type_().as_str().to_owned()),
            Some("o".into())
        );
        let bare = NowPlaying::default().metadata();
        let bare = glib::VariantDict::new(Some(&bare));
        assert!(bare.lookup_value("mpris:artUrl", None).is_none());
        assert!(bare.lookup_value("xesam:artist", None).is_none());
    }

    #[test]
    fn only_what_changed_is_announced() {
        let before = Shown::default();
        let mut after = before.clone();
        assert_eq!(after.changed_since(&before), None);
        after.status = PlayState::Playing;
        after.can_go_next = true;
        let payload = after.changed_since(&before).expect("a change");
        assert_eq!(payload.type_().as_str(), "(sa{sv}as)");
        let changed = glib::VariantDict::new(Some(&payload.child_value(1)));
        assert_eq!(
            changed.lookup::<String>("PlaybackStatus").unwrap(),
            Some("Playing".into())
        );
        assert_eq!(changed.lookup::<bool>("CanGoNext").unwrap(), Some(true));
        assert!(changed.lookup_value("Rate", None).is_none());
    }

    #[test]
    fn calls_become_commands_and_unknown_ones_are_refused() {
        let none = ().to_variant();
        assert_eq!(command_of("PlayPause", &none), Some(Command::PlayPause));
        assert_eq!(
            command_of("Seek", &(5_000_000i64,).to_variant()),
            Some(Command::Seek(5_000_000))
        );
        let path = glib::variant::ObjectPath::try_from("/a/b".to_owned()).unwrap();
        assert_eq!(
            command_of("SetPosition", &(path, 3_000_000i64).to_variant()),
            Some(Command::SetPosition(Duration::from_secs(3)))
        );
        assert_eq!(command_of("OpenUri", &("x".to_owned(),).to_variant()), None);
        assert_eq!(root_property("Identity"), Some("StoryArc".to_variant()));
        assert_eq!(root_property("CanQuit"), Some(false.to_variant()));
    }

    /// The test's own main context, pushed as the thread default: the egress test's GTK
    /// owns the process's default context from its own thread.
    fn with_context(test: impl FnOnce(&glib::MainContext)) {
        let context = glib::MainContext::new();
        context
            .with_thread_default(|| test(&context))
            .expect("the context is this thread's");
    }

    fn pump_until(deadline: Duration, mut done: impl FnMut() -> bool) -> bool {
        let context = glib::MainContext::thread_default().unwrap_or_default();
        let end = Instant::now() + deadline;
        while Instant::now() < end {
            context.iteration(false);
            if done() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        false
    }

    /// Runs `playerctl` against the private bus while the main context turns.
    fn playerctl(address: &str, args: &[&str]) -> String {
        let (tx, rx) = std::sync::mpsc::channel();
        let address = address.to_owned();
        let args: Vec<String> = args.iter().map(|a| (*a).to_owned()).collect();
        std::thread::spawn(move || {
            // Bounded, so a bus that never answers shows as output rather than a hang.
            let output = Process::new("timeout")
                .args(["20", "playerctl", "-p", "storyarc"])
                .args(&args)
                .env("DBUS_SESSION_BUS_ADDRESS", &address)
                .output();
            let _ = tx.send(output);
        });
        let mut result = None;
        assert!(
            pump_until(Duration::from_secs(10), || {
                result = rx.try_recv().ok();
                result.is_some()
            }),
            "playerctl did not answer"
        );
        let output = result.unwrap().expect("playerctl runs");
        format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        )
        .trim()
        .to_owned()
    }

    #[test]
    fn playerctl_controls_playback_and_shows_the_metadata() {
        with_context(playerctl_walk);
    }

    fn playerctl_walk(context: &glib::MainContext) {
        // A tool counts only when it runs: under emulated amd64 a missing program can spawn
        // as Ok with a failing status instead of an error (the Arch row on Apple silicon).
        let runs = |tool: &str| {
            Process::new(tool)
                .arg("--version")
                .output()
                .is_ok_and(|output| output.status.success())
        };
        if !runs("dbus-daemon") {
            eprintln!("skipped: no dbus-daemon");
            return;
        }
        if !runs("playerctl") {
            eprintln!("skipped: no playerctl");
            return;
        }
        // A private session bus for this test alone, run by GLib's own test helper.
        let bus = gio::TestDBus::new(gio::TestDBusFlags::NONE);
        bus.up();
        let address = bus.bus_address().map(|a| a.to_string()).unwrap_or_default();
        assert!(address.contains("unix:"), "no bus address: {address:?}");
        eprintln!("mpris: private bus up");
        let connection = context
            .block_on(gio::DBusConnection::for_address_future(
                &address,
                gio::DBusConnectionFlags::AUTHENTICATION_CLIENT
                    | gio::DBusConnectionFlags::MESSAGE_BUS_CONNECTION,
                None,
            ))
            .expect("a connection to the private bus");
        let heard: Rc<RefCell<Vec<Command>>> = Rc::default();
        let log = heard.clone();
        let mpris = Mpris::publish(connection.clone(), move |command| {
            log.borrow_mut().push(command)
        })
        .expect("published");
        let mut shown = Shown {
            status: PlayState::Playing,
            position: Duration::from_secs(1),
            now: now_playing(),
            can_go_next: true,
            ..Shown::default()
        };
        mpris.show(shown.clone(), false);
        pump_until(Duration::from_millis(300), || false);
        eprintln!("mpris: published, asking playerctl");

        assert_eq!(playerctl(&address, &["status"]), "Playing");
        eprintln!("mpris: playerctl read the status");
        assert_eq!(playerctl(&address, &["metadata", "title"]), "Natural Sort");
        assert_eq!(
            playerctl(&address, &["metadata", "mpris:artUrl"]),
            "file:///tmp/cover.png"
        );
        // playerctl adds the time since the last report while the status is Playing.
        let position: f64 = playerctl(&address, &["position"])
            .parse()
            .expect("a number");
        assert!((1.0..1.5).contains(&position), "{position}");

        playerctl(&address, &["play-pause"]);
        assert_eq!(heard.borrow().last(), Some(&Command::PlayPause));
        shown.status = PlayState::Paused;
        mpris.show(shown.clone(), false);
        assert_eq!(playerctl(&address, &["status"]), "Paused");

        playerctl(&address, &["position", "3"]);
        assert_eq!(
            heard.borrow().last(),
            Some(&Command::SetPosition(Duration::from_secs(3)))
        );
        shown.position = Duration::from_secs(3);
        mpris.show(shown, true);
        assert_eq!(playerctl(&address, &["position"]), "3.000000");

        playerctl(&address, &["next"]);
        assert_eq!(heard.borrow().last(), Some(&Command::Next));

        drop(mpris);
        pump_until(Duration::from_millis(300), || false);
        let gone = playerctl(&address, &["status"]);
        assert!(
            gone.contains("No player") || gone.contains("not found") || gone.is_empty(),
            "{gone}"
        );
        drop(connection);
        bus.down();
    }
}
