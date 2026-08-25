import Foundation

/// One pixel, as three channels.
///
/// A named value rather than a tuple: three members is where a tuple stops
/// documenting itself, and a test that compares colours should say which channel
/// it means.
struct SampledPixel: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}
