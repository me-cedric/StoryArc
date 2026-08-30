internal import Foundation

/// Range checks for numbers that came out of an untrusted archive header.
///
/// Swift traps on signed overflow, and **a trap is not a catchable error**. A ZIP64
/// offset field near `Int64.max`, or a GNU base-256 TAR size field, reaches the reader
/// as an ordinary `Int64`; the moment a bounds guard writes `offset + count` on one of
/// them the process aborts, on a file the reader did nothing but open. `ZipError` never
/// gets thrown, no `catch` runs, and the scan that found the file runs again on the next
/// launch — so one crafted archive in a watched folder is a crash at every start.
///
/// Every value taken from a header is therefore checked here at the point it is parsed,
/// and the checks themselves report overflow rather than performing it. Android needs
/// none of this: Kotlin wraps silently and the wrapped negative is refused by
/// `readExactly`, which is why this file has no Kotlin mirror.
enum HeaderBounds {
    /// Whether `count` bytes starting at `offset` really are inside `length` bytes.
    ///
    /// The addition reports overflow instead of performing it, which is the whole point:
    /// both operands are attacker-chosen, and their sum is exactly what traps.
    static func span(offset: Int64, count: Int64, fitsIn length: Int64) -> Bool {
        guard offset >= 0, count >= 0 else { return false }
        let (end, overflowed) = offset.addingReportingOverflow(count)
        return !overflowed && end <= length
    }

    /// Whether a header's offset or length names a position inside `length` bytes.
    ///
    /// An uncompressed size is deliberately *not* checked with this: compression means a
    /// value larger than the file is honest there. Everything else — a local header
    /// offset, a central directory offset, a compressed size — is a lie when it is.
    static func position(_ value: Int64, fitsIn length: Int64) -> Bool {
        value >= 0 && value <= length
    }
}
