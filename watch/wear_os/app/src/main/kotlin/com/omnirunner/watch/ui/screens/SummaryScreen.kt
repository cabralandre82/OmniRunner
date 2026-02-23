package com.omnirunner.watch.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.omnirunner.watch.R
import com.omnirunner.watch.service.WearWorkoutManager

/**
 * Post-workout summary screen.
 *
 * Uses ScalingLazyColumn for idiomatic Wear OS scrolling with
 * edge scaling effect.
 *
 * Mirrors the Apple Watch SummaryView from ContentView.swift.
 */
@Composable
fun SummaryScreen(manager: WearWorkoutManager) {
    val avgHr by manager.averageHeartRate.collectAsState()
    val maxHr by manager.maxHeartRate.collectAsState()
    val hrSamples by manager.hrSamples.collectAsState()
    val gpsPoints by manager.gpsPoints.collectAsState()

    val listState = rememberScalingLazyListState()

    ScalingLazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colors.background),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Header
        item {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(top = 24.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        painter = painterResource(id = R.drawable.ic_check),
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                        tint = Color(0xFF4CAF50),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Corrida Finalizada",
                        style = MaterialTheme.typography.title3,
                        color = Color.White,
                    )
                }
            }
        }

        // Primary stats: time + distance
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                SummaryStat(
                    value = manager.formattedElapsedTime(),
                    label = "Tempo",
                    color = Color.Yellow,
                )
                SummaryStat(
                    value = manager.formattedDistance(),
                    label = "Distância",
                    color = Color(0xFF4CAF50),
                )
            }
        }

        // Pace
        item {
            SummaryRow(
                iconRes = R.drawable.ic_timer,
                label = "Pace médio",
                value = "${manager.formattedPace()} /km",
            )
        }

        // Average HR
        item {
            SummaryRow(
                iconRes = R.drawable.ic_heart,
                label = "FC média",
                value = "$avgHr BPM",
            )
        }

        // Max HR
        item {
            SummaryRow(
                iconRes = R.drawable.ic_heart,
                label = "FC máxima",
                value = "$maxHr BPM",
            )
        }

        // GPS points
        item {
            SummaryRow(
                iconRes = R.drawable.ic_location,
                label = "GPS points",
                value = "${gpsPoints.size}",
            )
        }

        // HR samples
        item {
            Text(
                text = "${hrSamples.size} HR samples · ${gpsPoints.size} GPS pts",
                fontSize = 10.sp,
                color = Color(0xFF757575),
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(vertical = 4.dp),
            )
        }

        // New run button
        item {
            Button(
                onClick = { manager.reset() },
                colors = ButtonDefaults.buttonColors(
                    backgroundColor = Color(0xFF4CAF50),
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .height(44.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        painter = painterResource(id = R.drawable.ic_refresh),
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = Color.Black,
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Nova Corrida",
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black,
                    )
                }
            }
        }
    }
}

// ── Components ─────────────────────────────────────────────────

@Composable
private fun SummaryStat(
    value: String,
    label: String,
    color: Color,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = value,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            fontSize = 16.sp,
            color = color,
        )
        Text(
            text = label,
            fontSize = 9.sp,
            color = Color(0xFFB0BEC5),
        )
    }
}

@Composable
private fun SummaryRow(
    iconRes: Int,
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            painter = painterResource(id = iconRes),
            contentDescription = null,
            modifier = Modifier.size(12.dp),
            tint = Color(0xFFB0BEC5),
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = label,
            fontSize = 12.sp,
            color = Color(0xFFB0BEC5),
        )
        Spacer(modifier = Modifier.weight(1f))
        Text(
            text = value,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            fontSize = 13.sp,
            color = Color.White,
        )
    }
}
