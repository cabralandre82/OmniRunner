package com.omnirunner.watch.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.dialog.Alert
import com.omnirunner.watch.R
import com.omnirunner.watch.service.WearWorkoutManager
import com.omnirunner.watch.ui.components.HrZoneIndicator

/**
 * Main workout screen with horizontal pager (3 pages):
 *
 * - Page 0: Primary metrics (time, HR, distance, pace)
 * - Page 1: Detail metrics (avg HR, max HR, GPS count, HR count)
 * - Page 2: Controls (pause/resume, end with confirmation)
 *
 * Mirrors the Apple Watch WorkoutTabView from ContentView.swift.
 */
@Composable
fun WorkoutScreen(manager: WearWorkoutManager) {
    val pagerState = rememberPagerState(pageCount = { 3 })

    Box(modifier = Modifier.fillMaxSize()) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize(),
        ) { page ->
            when (page) {
                0 -> MetricsPage(manager)
                1 -> DetailsPage(manager)
                2 -> ControlsPage(manager)
            }
        }

        // Page indicator dots
        PageIndicator(
            pageCount = 3,
            currentPage = pagerState.currentPage,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 4.dp),
        )
    }
}

// ═══════════════════════════════════════════════════════════════
//  Page 0 — Primary Metrics
// ═══════════════════════════════════════════════════════════════

@Composable
private fun MetricsPage(manager: WearWorkoutManager) {
    val hr by manager.currentHeartRate.collectAsState()
    val distance by manager.totalDistanceMeters.collectAsState()
    val state by manager.state.collectAsState()
    val hasGps by manager.hasGpsFix.collectAsState()

    val isPaused = state == WearWorkoutManager.WorkoutState.PAUSED

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colors.background)
            .padding(horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        // Elapsed time — hero metric
        Text(
            text = manager.formattedElapsedTime(),
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            fontSize = 32.sp,
            color = Color.Yellow,
            textAlign = TextAlign.Center,
        )

        // Divider
        Box(
            modifier = Modifier
                .padding(vertical = 3.dp, horizontal = 16.dp)
                .fillMaxWidth()
                .height(1.dp)
                .background(Color(0xFF333333)),
        )

        // HR with zone color
        HrZoneIndicator(bpm = hr)

        // Divider
        Box(
            modifier = Modifier
                .padding(vertical = 3.dp, horizontal = 16.dp)
                .fillMaxWidth()
                .height(1.dp)
                .background(Color(0xFF333333)),
        )

        // Distance + Pace side by side
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Distance
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = formatDistanceValue(distance),
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    fontSize = 20.sp,
                    color = Color(0xFF4CAF50),
                )
                Text(
                    text = "km",
                    fontSize = 10.sp,
                    color = Color(0xFFB0BEC5),
                )
            }

            // Vertical separator
            Box(
                modifier = Modifier
                    .width(1.dp)
                    .height(28.dp)
                    .background(Color(0xFF333333)),
            )

            // Pace
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = manager.formattedPace(),
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    fontSize = 20.sp,
                    color = Color(0xFF00BCD4),
                )
                Text(
                    text = "/km",
                    fontSize = 10.sp,
                    color = Color(0xFFB0BEC5),
                )
            }
        }

        // GPS status
        if (!hasGps) {
            Spacer(modifier = Modifier.height(3.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                Icon(
                    painter = painterResource(id = R.drawable.ic_location),
                    contentDescription = null,
                    modifier = Modifier.size(10.dp),
                    tint = Color(0xFFFF9800),
                )
                Spacer(modifier = Modifier.width(3.dp))
                Text(
                    text = "Aguardando GPS",
                    fontSize = 9.sp,
                    color = Color(0xFFFF9800),
                )
            }
        }

        // Paused badge
        if (isPaused) {
            Spacer(modifier = Modifier.height(3.dp))
            Text(
                text = "PAUSADO",
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = Color.Yellow,
                modifier = Modifier
                    .clip(RoundedCornerShape(4.dp))
                    .background(Color.Yellow.copy(alpha = 0.15f))
                    .padding(horizontal = 12.dp, vertical = 2.dp),
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════════
//  Page 1 — Detail Metrics
// ═══════════════════════════════════════════════════════════════

@Composable
private fun DetailsPage(manager: WearWorkoutManager) {
    val avgHr by manager.averageHeartRate.collectAsState()
    val maxHr by manager.maxHeartRate.collectAsState()
    val gpsPoints by manager.gpsPoints.collectAsState()
    val hrSamples by manager.hrSamples.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colors.background)
            .padding(horizontal = 12.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Detalhes",
            fontSize = 11.sp,
            color = Color(0xFFB0BEC5),
            modifier = Modifier.padding(bottom = 6.dp),
        )

        DetailRow(
            iconRes = R.drawable.ic_heart,
            label = "FC Média",
            value = "$avgHr",
            unit = "BPM",
            tint = Color.Red,
        )

        DetailRow(
            iconRes = R.drawable.ic_heart,
            label = "FC Máx",
            value = "$maxHr",
            unit = "BPM",
            tint = Color(0xFFFF9800),
        )

        DetailRow(
            iconRes = R.drawable.ic_timer,
            label = "Pace",
            value = manager.formattedPace(),
            unit = "/km",
            tint = Color(0xFF00BCD4),
        )

        DetailRow(
            iconRes = R.drawable.ic_location,
            label = "GPS",
            value = "${gpsPoints.size}",
            unit = "pts",
            tint = Color(0xFF4CAF50),
        )

        DetailRow(
            iconRes = R.drawable.ic_heart,
            label = "HR",
            value = "${hrSamples.size}",
            unit = "amostras",
            tint = Color.Red,
        )
    }
}

@Composable
private fun DetailRow(
    iconRes: Int,
    label: String,
    value: String,
    unit: String,
    tint: Color,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            painter = painterResource(id = iconRes),
            contentDescription = null,
            modifier = Modifier.size(12.dp),
            tint = tint,
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = label,
            fontSize = 11.sp,
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
        Spacer(modifier = Modifier.width(3.dp))
        Text(
            text = unit,
            fontSize = 9.sp,
            color = Color(0xFFB0BEC5),
        )
    }
}

// ═══════════════════════════════════════════════════════════════
//  Page 2 — Controls
// ═══════════════════════════════════════════════════════════════

@Composable
private fun ControlsPage(manager: WearWorkoutManager) {
    val state by manager.state.collectAsState()
    val isPaused = state == WearWorkoutManager.WorkoutState.PAUSED
    var showEndConfirmation by remember { mutableStateOf(false) }

    if (showEndConfirmation) {
        EndConfirmationDialog(
            onConfirm = {
                showEndConfirmation = false
                manager.endWorkout()
            },
            onDismiss = { showEndConfirmation = false },
        )
    } else {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colors.background)
                .padding(horizontal = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Pause / Resume button
            Button(
                onClick = {
                    if (isPaused) manager.resumeWorkout() else manager.pauseWorkout()
                },
                colors = ButtonDefaults.buttonColors(
                    backgroundColor = if (isPaused) {
                        Color(0xFF4CAF50)
                    } else {
                        Color(0xFFFFC107)
                    },
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        painter = painterResource(
                            id = if (isPaused) R.drawable.ic_play else R.drawable.ic_pause,
                        ),
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = Color.Black,
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = if (isPaused) "Retomar" else "Pausar",
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black,
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // End button
            Button(
                onClick = { showEndConfirmation = true },
                colors = ButtonDefaults.buttonColors(
                    backgroundColor = Color(0xFFF44336),
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        painter = painterResource(id = R.drawable.ic_stop),
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = Color.White,
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Encerrar",
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White,
                    )
                }
            }
        }
    }
}

@Composable
private fun EndConfirmationDialog(
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF1A1A1A))
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            painter = painterResource(id = R.drawable.ic_stop),
            contentDescription = null,
            modifier = Modifier.size(24.dp),
            tint = Color(0xFFF44336),
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Encerrar corrida?",
            style = MaterialTheme.typography.title3,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(4.dp))

        Text(
            text = "O treino será salvo.",
            fontSize = 12.sp,
            color = Color(0xFFB0BEC5),
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(16.dp))

        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Button(
                onClick = onDismiss,
                colors = ButtonDefaults.buttonColors(
                    backgroundColor = Color(0xFF424242),
                ),
                modifier = Modifier.size(ButtonDefaults.DefaultButtonSize),
            ) {
                Text(text = "Não", color = Color.White)
            }

            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(
                    backgroundColor = Color(0xFFF44336),
                ),
                modifier = Modifier.size(ButtonDefaults.DefaultButtonSize),
            ) {
                Text(text = "Sim", color = Color.White)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
//  Page Indicator Dots
// ═══════════════════════════════════════════════════════════════

@Composable
private fun PageIndicator(
    pageCount: Int,
    currentPage: Int,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(pageCount) { index ->
            Box(
                modifier = Modifier
                    .size(if (index == currentPage) 6.dp else 4.dp)
                    .clip(CircleShape)
                    .background(
                        if (index == currentPage) Color.White else Color(0xFF666666),
                    ),
            )
        }
    }
}

// ═══════════════════════════════════════════════════════════════
//  Helpers
// ═══════════════════════════════════════════════════════════════

private fun formatDistanceValue(meters: Double): String {
    val km = meters / 1000.0
    return if (km >= 10) {
        String.format("%.1f", km)
    } else {
        String.format("%.2f", km)
    }
}
