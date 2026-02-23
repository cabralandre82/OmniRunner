package com.omnirunner.watch.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.omnirunner.watch.R
import com.omnirunner.watch.domain.models.HrZone

/**
 * Displays the current heart rate with zone-colored styling.
 *
 * Shows: ♥ 155 BPM  Z3
 *
 * Port of the Apple Watch HrZone coloring from HrZoneHelper.swift.
 */
@Composable
fun HrZoneIndicator(
    bpm: Int,
    maxHr: Int = 190,
    modifier: Modifier = Modifier,
) {
    val zone = HrZone.zoneFor(bpm, maxHr)
    val zoneColor = Color(zone.color)

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Icon(
            painter = painterResource(id = R.drawable.ic_heart),
            contentDescription = "Heart Rate",
            modifier = Modifier.size(16.dp),
            tint = zoneColor,
        )

        Spacer(modifier = Modifier.width(4.dp))

        Text(
            text = if (bpm > 0) "$bpm" else "--",
            style = MaterialTheme.typography.title1.copy(
                fontWeight = FontWeight.Bold,
            ),
            color = zoneColor,
        )

        Spacer(modifier = Modifier.width(4.dp))

        Text(
            text = "BPM",
            style = MaterialTheme.typography.caption2,
            color = Color(0xFFB0BEC5),
        )

        if (bpm > 0 && zone != HrZone.BELOW_ZONES) {
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = "Z${zone.zoneNumber}",
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = zoneColor,
            )
        }
    }
}
