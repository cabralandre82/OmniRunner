package com.omnirunner.watch.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.omnirunner.watch.R

/**
 * Full-screen start view shown before a workout begins.
 *
 * Mirrors the Apple Watch StartView from ContentView.swift.
 */
@Composable
fun StartScreen(
    onStartClick: () -> Unit = {},
) {
    var isLoading by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colors.background),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(modifier = Modifier.weight(1f))

        Icon(
            painter = painterResource(id = R.drawable.ic_run),
            contentDescription = "Run",
            modifier = Modifier.size(40.dp),
            tint = MaterialTheme.colors.primary,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Omni Runner",
            style = MaterialTheme.typography.title3,
            color = MaterialTheme.colors.onBackground,
        )

        Spacer(modifier = Modifier.height(4.dp))

        Text(
            text = "WearOS",
            style = MaterialTheme.typography.caption2,
            color = MaterialTheme.colors.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.weight(1f))

        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(40.dp),
                indicatorColor = MaterialTheme.colors.primary,
                trackColor = Color(0xFF333333),
                strokeWidth = 3.dp,
            )
        } else {
            Button(
                onClick = {
                    isLoading = true
                    onStartClick()
                },
                colors = ButtonDefaults.buttonColors(
                    backgroundColor = MaterialTheme.colors.primary,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
                    .weight(0f, fill = false),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        painter = painterResource(id = R.drawable.ic_play),
                        contentDescription = "Start",
                        modifier = Modifier.size(20.dp),
                        tint = Color.Black,
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Iniciar Corrida",
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black,
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
    }
}
