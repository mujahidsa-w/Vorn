import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'chat_screen.dart';
import 'data.dart';
import 'firebase_options.dart';
import 'rooms_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const VexoApp());
}

class VexoApp extends StatelessWidget {
  const VexoApp({super.key});

  static const _seed = Color(0xFF7C5CFF);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vexo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true, brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const RootGate(),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  final _auth = AuthService();
  final _chat = ChatService();

  UserProfile? _me;
  Room? _room;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      _me = await _auth.currentProfile();
    } catch (_) {
      _me = null;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _me = null;
      _room = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final me = _me;
    if (me == null) {
      return AuthScreen(
        auth: _auth,
        onSignedIn: (profile) => setState(() => _me = profile),
      );
    }
    final room = _room;
    if (room == null) {
      return RoomsScreen(
        chat: _chat,
        onOpen: (r) => setState(() => _room = r),
        onSignOut: _signOut,
      );
    }
    return ChatScreen(
      room: room,
      me: me,
      chat: _chat,
      onBack: () => setState(() => _room = null),
    );
  }
}
