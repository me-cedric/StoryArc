//! The one async runtime the core owns (design.md, Open Question 5: tokio).
//!
//! The sources that speak a network protocol are async underneath: `smb` runs on tokio, and so
//! do the HTTP clients of OPDS and Kavita. Everything the apps call stays synchronous, as the
//! rest of the core is, so a GTK worker thread and a C# `Task.Run` call it the same way. The
//! bridge is this handle: a host creates one [`Runtime`] at start, hands clones to the sources
//! it opens, and each blocking call runs its future here.
//!
//! **Never call a blocking source method from inside the runtime itself.** `block_on` from a
//! runtime thread panics by design; the apps call the core from their own worker threads, which
//! is what the facade already asks of them.

use std::future::Future;
use std::sync::Arc;
use std::time::Duration;

/// A shared multi-threaded tokio runtime. Cheap to clone: every clone is the same runtime.
#[derive(Clone)]
pub struct Runtime {
    inner: Arc<tokio::runtime::Runtime>,
}

impl Runtime {
    /// Starts the runtime with two worker threads: the core waits on sockets, it does not
    /// compute on this pool, so two are enough for a reader's reads and a download at once.
    pub fn new() -> std::io::Result<Self> {
        let inner = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("storyarc-core-io")
            .enable_all()
            .build()?;
        Ok(Self {
            inner: Arc::new(inner),
        })
    }

    /// Runs `future` to completion on this runtime and returns its output, blocking the
    /// calling thread. The calling thread must not be one of the runtime's own.
    pub fn block_on<F: Future>(&self, future: F) -> F::Output {
        self.inner.handle().block_on(future)
    }

    /// Runs `future` with a deadline: `None` when it did not finish within `limit`.
    pub fn block_on_within<F: Future>(&self, limit: Duration, future: F) -> Option<F::Output> {
        self.block_on(async move { tokio::time::timeout(limit, future).await.ok() })
    }

    /// Starts `future` on the runtime without waiting for it.
    pub fn spawn<F>(&self, future: F) -> tokio::task::JoinHandle<F::Output>
    where
        F: Future + Send + 'static,
        F::Output: Send + 'static,
    {
        self.inner.spawn(future)
    }
}

/// A value whose drop must run inside the runtime.
///
/// The `smb` crate's handles spawn their own clean-up task when they are dropped, and spawning
/// outside a tokio context panics. A session dropped by a reader thread — on a reconnect, or
/// when a window closes — is exactly that, so every such handle is held in one of these, and
/// its drop enters the runtime first.
pub struct InRuntime<T> {
    value: Option<T>,
    runtime: Runtime,
}

impl<T> InRuntime<T> {
    pub fn new(runtime: &Runtime, value: T) -> Self {
        Self {
            value: Some(value),
            runtime: runtime.clone(),
        }
    }
}

impl<T> std::ops::Deref for InRuntime<T> {
    type Target = T;

    fn deref(&self) -> &T {
        self.value.as_ref().expect("taken only by drop")
    }
}

impl<T> Drop for InRuntime<T> {
    fn drop(&mut self) {
        let _context = self.runtime.inner.enter();
        drop(self.value.take());
    }
}

impl std::fmt::Debug for Runtime {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Runtime")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_blocking_call_returns_the_future_output() {
        let runtime = Runtime::new().unwrap();
        assert_eq!(runtime.block_on(async { 6 * 7 }), 42);
    }

    #[test]
    fn a_deadline_that_passes_answers_none() {
        let runtime = Runtime::new().unwrap();
        let late = runtime.block_on_within(Duration::from_millis(20), async {
            tokio::time::sleep(Duration::from_secs(5)).await;
        });
        assert!(late.is_none());
        let early = runtime.block_on_within(Duration::from_secs(5), async { "done" });
        assert_eq!(early, Some("done"));
    }

    /// Spawns on drop, as the `smb` crate's handles do.
    struct SpawnsOnDrop(std::sync::mpsc::Sender<&'static str>);

    impl Drop for SpawnsOnDrop {
        fn drop(&mut self) {
            let sender = self.0.clone();
            tokio::task::spawn(async move { sender.send("cleaned up").ok() });
        }
    }

    #[test]
    fn a_value_that_spawns_on_drop_is_dropped_inside_the_runtime() {
        let runtime = Runtime::new().unwrap();
        let (sender, receiver) = std::sync::mpsc::channel();
        let held = InRuntime::new(&runtime, SpawnsOnDrop(sender));
        // Outside the runtime: without the wrapper this drop panics.
        drop(held);
        assert_eq!(
            receiver.recv_timeout(Duration::from_secs(5)),
            Ok("cleaned up")
        );
    }

    #[test]
    fn clones_share_one_runtime_across_threads() {
        let runtime = Runtime::new().unwrap();
        let clone = runtime.clone();
        let answer = std::thread::spawn(move || clone.block_on(async { 1 }))
            .join()
            .unwrap();
        assert_eq!(answer + runtime.block_on(async { 1 }), 2);
    }
}
