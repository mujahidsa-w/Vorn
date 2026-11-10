import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}

String friendlyError(Object e) {
  if (e is AppException) return e.message;
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'اسم المستخدم أو كلمة السر غلط';
      case 'email-already-in-use':
        return 'اسم المستخدم مستخدم، جرّب غيره';
      case 'weak-password':
        return 'كلمة السر ضعيفة (6 أحرف على الأقل)';
      case 'network-request-failed':
        return 'مشكلة بالنت، تأكد من الاتصال';
      case 'too-many-requests':
        return 'محاولات كتير، استنى شوي';
      case 'api-key-not-valid':
        return 'مفتاح Firebase مش صالح لهالمنصة';
      case 'operation-not-allowed':
        return 'تسجيل الدخول بالإيميل وكلمة السر مش مفعّل بـ Firebase';
      default:
        return 'خطأ بتسجيل الدخول (${e.code})';
    }
  }
  if (e is FirebaseException) return 'خطأ بالداتابيز (${e.code})';
  return 'صار خطأ غير متوقع';
}

class UserProfile {
  final String uid;
  final String displayName;
  const UserProfile({required this.uid, required this.displayName});
}

class Room {
  final String id;
  final String title;
  final String game;
  const Room({required this.id, required this.title, required this.game});

  factory Room.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return Room(
      id: d.id,
      title: m['title'] as String? ?? 'بدون اسم',
      game: m['game'] as String? ?? '',
    );
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String type;
  final String text;
  final String audioUrl;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.type,
    required this.text,
    required this.audioUrl,
  });

  bool get isAudio => type == 'AUDIO';

  factory ChatMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return ChatMessage(
      id: d.id,
      senderId: m['senderId'] as String? ?? '',
      senderName: m['senderName'] as String? ?? '',
      type: m['type'] as String? ?? 'TEXT',
      text: m['text'] as String? ?? '',
      audioUrl: m['audioUrl'] as String? ?? '',
    );
  }
}

/// Username + password login. Firebase Auth needs an email,
/// so each username maps to <username>@vexo.local.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final RegExp _usernameRule = RegExp(r'^[a-z0-9_]{3,20}$');

  String _normalize(String u) => u.trim().toLowerCase();
  String _emailFor(String key) => '$key@vexo.local';

  Future<UserProfile?> currentProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _loadProfile(user.uid);
  }

  Future<UserProfile?> _loadProfile(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    final data = snap.data();
    if (data == null) return null;
    return UserProfile(uid: uid, displayName: data['displayName'] as String? ?? '');
  }

  Future<UserProfile> signIn(String username, String password) async {
    final key = _normalize(username);
    final cred = await _auth.signInWithEmailAndPassword(
      email: _emailFor(key),
      password: password,
    );
    final profile = await _loadProfile(cred.user!.uid);
    if (profile == null) throw const AppException('الحساب ما إله بيانات');
    return profile;
  }

  Future<UserProfile> signUp(String username, String displayName, String password) async {
    final key = _normalize(username);
    final name = displayName.trim();

    if (!_usernameRule.hasMatch(key)) {
      throw const AppException('اسم المستخدم 3-20 حرف (إنجليزي، أرقام، _)');
    }
    if (name.isEmpty) throw const AppException('الاسم الظاهر مطلوب');
    if (password.length < 6) throw const AppException('كلمة السر 6 أحرف على الأقل');

    final taken = await _db.collection('usernames').doc(key).get();
    if (taken.exists) throw const AppException('اسم المستخدم مستخدم، جرّب غيره');

    final cred = await _auth.createUserWithEmailAndPassword(
      email: _emailFor(key),
      password: password,
    );
    final uid = cred.user!.uid;

    final batch = _db.batch();
    batch.set(_db.collection('usernames').doc(key), {'uid': uid});
    batch.set(_db.collection('users').doc(uid), {
      'uid': uid,
      'name': key,
      'displayName': name,
    });
    await batch.commit();

    return UserProfile(uid: uid, displayName: name);
  }

  Future<void> signOut() => _auth.signOut();
}

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Stream<List<Room>> rooms() {
    return _db.collection('rooms').snapshots().map(
          (s) => s.docs.map(Room.fromDoc).toList(),
        );
  }

  Stream<List<ChatMessage>> messages(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(200)
        .snapshots()
        .map((s) => s.docs.map(ChatMessage.fromDoc).toList());
  }

  Future<void> sendText(String roomId, UserProfile me, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    await _post(roomId, me, type: 'TEXT', text: body, audioUrl: '');
  }

  Future<void> sendAudio(String roomId, UserProfile me, String filePath) async {
    final name = '${DateTime.now().microsecondsSinceEpoch}.m4a';
    final ref = _storage.ref('voice/$roomId/$name');
    await ref.putFile(File(filePath), SettableMetadata(contentType: 'audio/mp4'));
    final url = await ref.getDownloadURL();
    await _post(roomId, me, type: 'AUDIO', text: '', audioUrl: url);
  }

  Future<void> _post(
    String roomId,
    UserProfile me, {
    required String type,
    required String text,
    required String audioUrl,
  }) async {
    await _db.collection('rooms').doc(roomId).collection('messages').add({
      'senderId': me.uid,
      'senderName': me.displayName,
      'type': type,
      'text': text,
      'audioUrl': audioUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
