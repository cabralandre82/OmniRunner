import Foundation

/// A single heart rate reading captured during a workout.
///
/// Mirrors the wire format defined in `docs/WatchArchitecture.md`.
struct HeartRateSample: Codable, Sendable {
    let bpm: Int
    let timestampMs: Int64
}
