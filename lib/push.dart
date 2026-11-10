import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';

/// Gets this device's FCM token and saves it on the user profile.
/// On web the browser only allows the permission prompt after a tap, so web
/// callers use [enablePush] from a button. Here we only pick up an existing grant.
Future<void> setupPush(String uid) async {
  try {
    final messaging = FirebaseMessaging.instance;
    if (!kIsWeb) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    }
    final token = await _token(messaging);
    if (token != null) {
      await _saveToken(uid, token);
    }
    messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
  } catch (e) {
    debugPrint('push setup failed: $e');
  }
}

/// Asks for notification permission (call from a button tap) and saves the token.
/// Returns true when the device can receive notifications.
Future<bool> enablePush(String uid) async {
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }
    final token = await _token(messaging);
    if (token == null) return false;
    await _saveToken(uid, token);
    messaging.onTokenRefresh.listen((t) => _saveToken(uid, t));
    return true;
  } catch (e) {
    debugPrint('enable push failed: $e');
    return false;
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

Future<String?> _token(FirebaseMessaging messaging) {
  if (kIsWeb) return messaging.getToken(vapidKey: DefaultFirebaseOptions.webVapidKey);
  return messaging.getToken();
}

Future<void> _saveToken(String uid, String token) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .set({'fcmToken': token}, SetOptions(merge: true));
}
