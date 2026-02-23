package com.omnirunner.watch.domain.usecases

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure-function Haversine distance calculator.
 *
 * Port of `omni_runner/lib/core/utils/haversine.dart`.
 * Uses the same Earth radius (6,371,000 m) for cross-platform consistency.
 */
object Haversine {

    private const val EARTH_RADIUS_METERS = 6_371_000.0

    /**
     * Great-circle distance in **meters** between two lat/lng points.
     */
    fun distanceMeters(
        lat1: Double, lng1: Double,
        lat2: Double, lng2: Double,
    ): Double {
        val dLat = toRadians(lat2 - lat1)
        val dLng = toRadians(lng2 - lng1)

        val lat1Rad = toRadians(lat1)
        val lat2Rad = toRadians(lat2)

        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1Rad) * cos(lat2Rad) *
            sin(dLng / 2) * sin(dLng / 2)

        val c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return EARTH_RADIUS_METERS * c
    }

    private fun toRadians(degrees: Double): Double =
        degrees * (Math.PI / 180.0)
}
