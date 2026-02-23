import Foundation

/// Pure-function Haversine distance calculator.
///
/// Port of `omni_runner/lib/core/utils/haversine.dart`.
/// Uses the same Earth radius (6,371,000 m) for consistency.
enum Haversine {
    static let earthRadiusMeters: Double = 6_371_000.0

    /// Great-circle distance in **meters** between two lat/lng points.
    static func distanceMeters(
        lat1: Double, lng1: Double,
        lat2: Double, lng2: Double
    ) -> Double {
        let dLat = toRadians(lat2 - lat1)
        let dLng = toRadians(lng2 - lng1)

        let lat1Rad = toRadians(lat1)
        let lat2Rad = toRadians(lat2)

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1Rad) * cos(lat2Rad)
            * sin(dLng / 2) * sin(dLng / 2)

        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusMeters * c
    }

    private static func toRadians(_ degrees: Double) -> Double {
        degrees * (.pi / 180.0)
    }
}
