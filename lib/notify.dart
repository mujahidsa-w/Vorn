import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cloudflare Worker that sends push notifications (see worker/).
/// Set this after `wrangler deploy`, e.g. https://vexo-notify.<account>.workers.dev/notify
const String notifyWorkerUrl = 'REPLACE_WORKER_URL';

/// Tells the Worker that a message was written so it can push to the other members.
/// Errors are ignored: a failed push must never block sending the message.
Future<void> notifyNewMessage(String roomId, String msgId) async {
  if (notifyWorkerUrl.startsWith('REPLACE')) return;
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final idToken = await user.getIdToken();
    await http
        .post(
          Uri.parse(notifyWorkerUrl),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'roomId': roomId, 'msgId': msgId}),
        )
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('notify failed: $e');
  }
}
