package com.omnirunner.watch.domain.usecases

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Haversine distance tests — mirrors the Dart tests in
 * `omni_runner/test/core/utils/haversine_test.dart`.
 */
class HaversineTest {

    @Test
    fun `same point returns zero`() {
        val result = Haversine.distanceMeters(
            lat1 = -23.5505, lng1 = -46.6333,
            lat2 = -23.5505, lng2 = -46.6333,
        )
        assertEquals(0.0, result, 0.001)
    }

    @Test
    fun `known distance Sao Paulo to Rio`() {
        val result = Haversine.distanceMeters(
            lat1 = -23.5505, lng1 = -46.6333,
            lat2 = -22.9068, lng2 = -43.1729,
        )
        // ~357 km
        assertTrue("Expected ~357km, got ${result / 1000}km", result > 350_000 && result < 365_000)
    }

    @Test
    fun `short distance approximately 100m`() {
        val result = Haversine.distanceMeters(
            lat1 = -23.5505, lng1 = -46.6333,
            lat2 = -23.5514, lng2 = -46.6333,
        )
        // ~100m
        assertTrue("Expected ~100m, got ${result}m", result > 90 && result < 110)
    }

    @Test
    fun `antipodal points return half circumference`() {
        val result = Haversine.distanceMeters(
            lat1 = 0.0, lng1 = 0.0,
            lat2 = 0.0, lng2 = 180.0,
        )
        // Half circumference ~20,015 km
        assertTrue(
            "Expected ~20015km, got ${result / 1000}km",
            result > 20_000_000 && result < 20_050_000,
        )
    }

    @Test
    fun `very small distance around 5 meters GPS scale`() {
        val result = Haversine.distanceMeters(
            lat1 = -23.5505, lng1 = -46.6333,
            lat2 = -23.55054, lng2 = -46.6333,
        )
        assertTrue("Expected ~4-5m, got ${result}m", result > 3 && result < 7)
    }

    @Test
    fun `crossing the prime meridian`() {
        val result = Haversine.distanceMeters(
            lat1 = 51.5074, lng1 = -0.1,
            lat2 = 51.5074, lng2 = 0.1,
        )
        assertTrue("Expected ~14km, got ${result / 1000}km", result > 12_000 && result < 15_000)
    }

    @Test
    fun `crossing the international date line`() {
        val result = Haversine.distanceMeters(
            lat1 = 0.0, lng1 = 179.9,
            lat2 = 0.0, lng2 = -179.9,
        )
        // 0.2 degrees at equator ≈ 22 km
        assertTrue("Expected ~22km, got ${result / 1000}km", result > 20_000 && result < 25_000)
    }

    @Test
    fun `consistency with Earth radius constant`() {
        assertEquals(6_371_000.0, Haversine.javaClass.getDeclaredField("EARTH_RADIUS_METERS").apply {
            isAccessible = true
        }.getDouble(null), 0.0)
    }
}
