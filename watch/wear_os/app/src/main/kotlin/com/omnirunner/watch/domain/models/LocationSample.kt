package com.omnirunner.watch.domain.models

data class LocationSample(
    val lat: Double,
    val lng: Double,
    val alt: Double,
    val accuracy: Float,
    val speed: Float,
    val timestampMs: Long,
)
