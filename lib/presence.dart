import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

Timer? _timer;

/// Keeps users/{uid}.lastSeen fresh while the app is signed in.
void startPresence(String uid) {
  _timer?.cancel();
  _touch(uid);
  _timer = Timer.periodic(const Duration(minutes: 2), (_) => _touch(uid));
}

void stopPresence() {
  _timer?.cancel();
  _timer = null;
}

Future<void> _touch(String uid) async {
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'lastSeen': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  } catch (_) {}
}
