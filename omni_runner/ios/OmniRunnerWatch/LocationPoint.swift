import Foundation

/// A single GPS point captured during a workout.
///
/// Mirrors the Flutter `LocationPointEntity` and the wire format
/// defined in `docs/WatchArchitecture.md`.
struct LocationPoint: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let accuracy: Double
    let speed: Double
    let timestampMs: Int64

    /// JSON keys matching the wire format.
    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lng"
        case altitude = "alt"
        case accuracy
        case speed
        case timestampMs
    }
}
