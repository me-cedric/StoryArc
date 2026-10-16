//! Reaching the bytes: every reader above this module takes a [`RandomAccessSource`] and
//! nothing else (ADR-0008).

pub mod source;
#[cfg(test)]
mod tests;

pub use source::{
    CancelToken, Cancellable, FileSource, HeaderBounds, MemorySource, RandomAccessSource,
    SourceError,
};
