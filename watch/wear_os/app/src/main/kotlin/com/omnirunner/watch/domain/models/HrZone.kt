package com.omnirunner.watch.domain.models

/**
 * Heart rate zones — exact port of the Dart HrZone enum.
 * Uses standard 5-zone model based on percentage of maxHR.
 */
enum class HrZone(val zoneNumber: Int, val label: String, val color: Long) {
    BELOW_ZONES(0, "Below Zones", 0xFF9E9E9E),
    ZONE_1(1, "Z1 — Easy", 0xFF2196F3),
    ZONE_2(2, "Z2 — Fat Burn", 0xFF4CAF50),
    ZONE_3(3, "Z3 — Aerobic", 0xFFFFEB3B),
    ZONE_4(4, "Z4 — Threshold", 0xFFFF9800),
    ZONE_5(5, "Z5 — Max", 0xFFF44336);

    companion object {
        fun zoneFor(bpm: Int, maxHr: Int): HrZone {
            if (maxHr <= 0 || bpm <= 0) return BELOW_ZONES
            val pct = bpm.toDouble() / maxHr.toDouble()
            return when {
                pct >= 0.90 -> ZONE_5
                pct >= 0.80 -> ZONE_4
                pct >= 0.70 -> ZONE_3
                pct >= 0.60 -> ZONE_2
                pct >= 0.50 -> ZONE_1
                else -> BELOW_ZONES
            }
        }
    }
}
