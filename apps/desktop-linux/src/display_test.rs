//! The tests that need a display run on one thread: GTK belongs to the thread that first
//! initialised it, and the test harness gives every test a thread of its own. Each display test
//! hands its body to this thread and waits for it. Without a display they skip by name, and
//! `scripts/headless-proof.sh` runs them under cage.

use std::sync::mpsc;
use std::sync::{Mutex, OnceLock};

type Outcome = std::thread::Result<()>;
type Order = (fn(), mpsc::Sender<Outcome>);

/// Runs `body` on the GTK thread, or skips when there is no display. A panic in the body is
/// the test's own panic.
pub fn on_display(body: fn()) {
    if std::env::var_os("WAYLAND_DISPLAY").is_none() && std::env::var_os("DISPLAY").is_none() {
        eprintln!("skipped: no display; scripts/headless-proof.sh runs this under cage");
        return;
    }
    static LINE: OnceLock<Mutex<mpsc::Sender<Order>>> = OnceLock::new();
    let line = LINE.get_or_init(|| {
        let (orders, inbox) = mpsc::channel::<Order>();
        std::thread::Builder::new()
            .name("gtk-tests".to_owned())
            .spawn(move || {
                gtk::init().expect("GTK on a display");
                adw::init().expect("libadwaita");
                for (body, answer) in inbox {
                    let _ = answer.send(std::panic::catch_unwind(body));
                }
            })
            .expect("the GTK thread");
        Mutex::new(orders)
    });
    let (answer, outcome) = mpsc::channel();
    line.lock()
        .expect("the GTK line")
        .send((body, answer))
        .expect("the GTK thread runs");
    if let Err(panic) = outcome.recv().expect("the GTK thread answers") {
        std::panic::resume_unwind(panic);
    }
}
