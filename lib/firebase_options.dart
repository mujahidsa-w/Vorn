import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase config for project ms-company-e7166.
/// Values come from google-services.json (Android) and GoogleService-Info.plist (iOS).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.iOS) return ios;
    return android;
  }

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
