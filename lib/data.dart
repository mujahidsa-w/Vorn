import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'countries.dart';

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
  final String fullPhone;
  const UserProfile({required this.uid, required this.displayName, this.fullPhone = ''});
}

class ContactEntry {
  final String uid;
  final String displayName;
  final String fullPhone;
  const ContactEntry({required this.uid, required this.displayName, required this.fullPhone});

  factory ContactEntry.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return ContactEntry(
      uid: m['uid'] as String? ?? d.id,
      displayName: m['displayName'] as String? ?? '',
      fullPhone: m['fullPhone'] as String? ?? '',
    );
  }
}

class Room {
  final String id;
  final String title;
  final String game;
  final String type; // 'group' or 'dm'
  final List<String> members;
  final Map<String, String> names;

  const Room({
    required this.id,
    required this.title,
    this.game = '',
    this.type = 'group',
    this.members = const [],
    this.names = const {},
  });

  bool get isDm => type == 'dm';

  /// For a direct chat, show the other person's name.
  String titleFor(String myUid) {
    if (!isDm) return title;
    for (final entry in names.entries) {
      if (entry.key != myUid) return entry.value;
    }
    return title;
  }

  factory Room.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return Room(
      id: d.id,
      title: m['title'] as String? ?? 'بدون اسم',
      game: m['game'] as String? ?? '',
      type: m['type'] as String? ?? 'group',
      members: List<String>.from(m['members'] as List? ?? const []),
      names: Map<String, String>.from(m['names'] as Map? ?? const {}),
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
  final int duration; // seconds, for voice notes
  final String mediaUrl; // image URL for IMAGE messages
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.type,
    required this.text,
    required this.audioUrl,
    this.duration = 0,
    this.mediaUrl = '',
    this.createdAt,
  });

  bool get isAudio => type == 'AUDIO';
  bool get isImage => type == 'IMAGE';

  factory ChatMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return ChatMessage(
      id: d.id,
      senderId: m['senderId'] as String? ?? '',
      senderName: m['senderName'] as String? ?? '',
      type: m['type'] as String? ?? 'TEXT',
      text: m['text'] as String? ?? '',
      audioUrl: m['audioUrl'] as String? ?? '',
      duration: (m['duration'] as num?)?.toInt() ?? 0,
      mediaUrl: m['mediaUrl'] as String? ?? '',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
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
    return UserProfile(
      uid: uid,
      displayName: data['displayName'] as String? ?? '',
      fullPhone: data['fullPhone'] as String? ?? '',
    );
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

  Future<UserProfile> signUp(
    String username,
    String displayName,
    String password,
    Country country,
  ) async {
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

    final phone = await _reservePhone(uid, country);

    final batch = _db.batch();
    batch.set(_db.collection('usernames').doc(key), {'uid': uid});
    batch.set(_db.collection('users').doc(uid), {
      'uid': uid,
      'name': key,
      'displayName': name,
      'country': country.iso,
      'fullPhone': phone,
    });
    await batch.commit();

    return UserProfile(uid: uid, displayName: name, fullPhone: phone);
  }

  /// Picks a random number under the country's dial code and reserves it.
  Future<String> _reservePhone(String uid, Country country) async {
    final rnd = Random.secure();
    for (var attempt = 0; attempt < 10; attempt++) {
      final local = List.generate(
        9,
        (i) => i == 0 ? (1 + rnd.nextInt(9)).toString() : rnd.nextInt(10).toString(),
      ).join();
      final full = '+${country.dial}$local';

      final reserved = await _db.runTransaction<bool>((tx) async {
        final ref = _db.collection('phones').doc(full);
        final snap = await tx.get(ref);
        if (snap.exists) return false;
        tx.set(ref, {'uid': uid});
        return true;
      });
      if (reserved) return full;
    }
    throw const AppException('ما قدرنا نعيّن رقم، جرّب مرة ثانية');
  }

  Future<void> signOut() => _auth.signOut();
}

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Group rooms are visible to everyone; direct chats only to their members.
  Stream<List<Room>> rooms(String myUid) {
    return _db.collection('rooms').snapshots().map(
          (s) => s.docs
              .map(Room.fromDoc)
              .where((r) => !r.isDm || r.members.contains(myUid))
              .toList(),
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

  Stream<List<ContactEntry>> contacts(String myUid) {
    return _db
        .collection('users')
        .doc(myUid)
        .collection('contacts')
        .snapshots()
        .map((s) => s.docs.map(ContactEntry.fromDoc).toList());
  }

  Future<UserProfile?> findByPhone(String fullPhone) async {
    final ph = await _db.collection('phones').doc(fullPhone).get();
    final uid = ph.data()?['uid'] as String?;
    if (uid == null) return null;
    final u = await _db.collection('users').doc(uid).get();
    final d = u.data();
    if (d == null) return null;
    return UserProfile(
      uid: uid,
      displayName: d['displayName'] as String? ?? '',
      fullPhone: d['fullPhone'] as String? ?? fullPhone,
    );
  }

  Future<void> addContact(UserProfile me, UserProfile other) async {
    await _db
        .collection('users')
        .doc(me.uid)
        .collection('contacts')
        .doc(other.uid)
        .set({
      'uid': other.uid,
      'displayName': other.displayName,
      'fullPhone': other.fullPhone,
    });
  }

  /// Opens (or creates) the direct chat between two users.
  Future<Room> openDm(UserProfile me, UserProfile other) async {
    final members = [me.uid, other.uid]..sort();
    final id = 'dm_${members.join('_')}';
    final names = {me.uid: me.displayName, other.uid: other.displayName};
    await _db.collection('rooms').doc(id).set({
      'type': 'dm',
      'members': members,
      'names': names,
      'title': other.displayName,
      'game': '',
    }, SetOptions(merge: true));
    return Room(id: id, title: other.displayName, type: 'dm', members: members, names: names);
  }

  Future<void> sendText(String roomId, UserProfile me, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    await _post(roomId, me, type: 'TEXT', text: body, audioUrl: '');
  }

  Future<void> sendAudio(String roomId, UserProfile me, String filePath, int duration) async {
    final name = '${DateTime.now().microsecondsSinceEpoch}.m4a';
    final ref = _storage.ref('voice/$roomId/$name');
    await ref.putFile(File(filePath), SettableMetadata(contentType: 'audio/mp4'));
    final url = await ref.getDownloadURL();
    await _post(roomId, me, type: 'AUDIO', text: '', audioUrl: url, duration: duration);
  }

  Future<void> sendImage(String roomId, UserProfile me, String filePath) async {
    final name = '${DateTime.now().microsecondsSinceEpoch}.jpg';
    final ref = _storage.ref('images/$roomId/$name');
    await ref.putFile(File(filePath), SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await _post(roomId, me, type: 'IMAGE', text: '', audioUrl: '', mediaUrl: url);
  }

  Future<void> _post(
    String roomId,
    UserProfile me, {
    required String type,
    required String text,
    required String audioUrl,
    int duration = 0,
    String mediaUrl = '',
  }) async {
    await _db.collection('rooms').doc(roomId).collection('messages').add({
      'senderId': me.uid,
      'senderName': me.displayName,
      'type': type,
      'text': text,
      'audioUrl': audioUrl,
      'duration': duration,
      'mediaUrl': mediaUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
