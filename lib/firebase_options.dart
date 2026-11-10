import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase config for project ms-company-e7166.
/// Values come from google-services.json (Android) and GoogleService-Info.plist (iOS).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.iOS) return ios;
    return android;
  }

  /// Web app config. Get it from Firebase console → Project settings → Your apps → Add app (Web).
  /// Replace every REPLACE_ value before the web build works.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_WEB_API_KEY',
    appId: 'REPLACE_WEB_APP_ID',
    messagingSenderId: '400730863326',
    projectId: 'ms-company-e7166',
    authDomain: 'ms-company-e7166.firebaseapp.com',
    storageBucket: 'ms-company-e7166.firebasestorage.app',
  );

  /// Web Push key pair. Firebase console → Project settings → Cloud Messaging → Web Push certificates.
  static const String webVapidKey = 'REPLACE_VAPID_KEY';

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC6sLLkrWvMnn1IIk7sA9uepsJwRPkV11k',
    appId: '1:400730863326:android:5d90f755f7aa0fde12744f',
    messagingSenderId: '400730863326',
    projectId: 'ms-company-e7166',
    storageBucket: 'ms-company-e7166.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA5h9Esy5G2TgxvHZKw6vcfOX5udXREb0U',
    appId: '1:400730863326:ios:f41ab51c330e9d3812744f',
    messagingSenderId: '400730863326',
    projectId: 'ms-company-e7166',
    storageBucket: 'ms-company-e7166.firebasestorage.app',
    iosBundleId: 'com.vexoapp.vexo',
  );
}
