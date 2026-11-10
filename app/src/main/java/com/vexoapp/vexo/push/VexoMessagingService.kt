package com.vexoapp.vexo.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Receives FCM pushes. Incoming-call full-screen UI and notification
 * channels get added in the calls stage.
 */
class VexoMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // TODO: save token to users/{uid}.fcmToken once calls/notifications are wired.
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // TODO: show notification for new messages / incoming calls.
    }
}
