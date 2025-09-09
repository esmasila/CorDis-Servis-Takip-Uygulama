package com.example.servis_takip_uygulama

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Background location tracking channel
            val locationChannel = NotificationChannel(
                "location_tracking",
                "Konum Takibi",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Servis konum takibi için gerekli"
                setShowBadge(false)
            }
            
            // General notifications channel
            val generalChannel = NotificationChannel(
                "general_notifications",
                "Genel Bildirimler",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Uygulama bildirimleri"
            }
            
            notificationManager.createNotificationChannel(locationChannel)
            notificationManager.createNotificationChannel(generalChannel)
        }
    }
}

// Updated


// Updated Again


