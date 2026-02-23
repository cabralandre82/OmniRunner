import SwiftUI

/// Standard 5-zone HR model. Port of `lib/domain/entities/hr_zone.dart`.
///
/// | Zone | %HRmax    | Description        |
/// |------|-----------|--------------------|
/// |  1   | 50 – 60 % | Recovery / warm-up |
/// |  2   | 60 – 70 % | Fat burn / easy    |
/// |  3   | 70 – 80 % | Aerobic / tempo    |
/// |  4   | 80 – 90 % | Threshold / hard   |
/// |  5   | 90 – 100% | VO₂ max            |
enum HrZone: Int, CaseIterable {
    case belowZones = 0
    case zone1 = 1
    case zone2 = 2
    case zone3 = 3
    case zone4 = 4
    case zone5 = 5

    var label: String {
        switch self {
        case .belowZones: return "Aquecendo"
        case .zone1: return "Z1 Recuperação"
        case .zone2: return "Z2 Aeróbico"
        case .zone3: return "Z3 Tempo"
        case .zone4: return "Z4 Limiar"
        case .zone5: return "Z5 VO₂ máx"
        }
    }

    var color: Color {
        switch self {
        case .belowZones: return .gray
        case .zone1: return .blue
        case .zone2: return .green
        case .zone3: return .yellow
        case .zone4: return .orange
        case .zone5: return .red
        }
    }

    var shortLabel: String {
        switch self {
        case .belowZones: return "--"
        case .zone1: return "Z1"
        case .zone2: return "Z2"
        case .zone3: return "Z3"
        case .zone4: return "Z4"
        case .zone5: return "Z5"
        }
    }

    /// Compute the HR zone for a given BPM and max HR.
    /// Matches the Dart implementation exactly.
    static func zoneFor(bpm: Int, maxHr: Int) -> HrZone {
        guard maxHr > 0, bpm > 0 else { return .belowZones }
        let pct = Double(bpm) / Double(maxHr)
        if pct >= 0.90 { return .zone5 }
        if pct >= 0.80 { return .zone4 }
        if pct >= 0.70 { return .zone3 }
        if pct >= 0.60 { return .zone2 }
        if pct >= 0.50 { return .zone1 }
        return .belowZones
    }
}
