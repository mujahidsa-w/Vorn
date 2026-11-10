import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Asks for notification permission and saves this device's FCM token on the user profile.
/// Cloud Functions read the token to send message and call notifications.
Future<void> setupPush(String uid) async {
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token != null) {
      await _saveToken(uid, token);
    }
    messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
  } catch (e) {
    debugPrint('push setup failed: $e');
  }
}

/// Removes this device's token on sign-out so the user stops getting notifications.
Future<void> clearPush(String uid) async {
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'fcmToken': FieldValue.delete()}, SetOptions(merge: true));
  } catch (e) {
    debugPrint('push clear failed: $e');
  }
}

Future<void> _saveToken(String uid, String token) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .set({'fcmToken': token}, SetOptions(merge: true));
}
