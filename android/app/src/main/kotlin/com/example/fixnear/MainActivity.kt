package com.example.fixnear

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    // Cloud Functions send to the "job_updates" channel. Android 8+ needs the
    // channel to exist before notifications on it can be shown.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "job_updates",
            "Job updates",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New jobs, quotes, status changes, payments and messages"
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
