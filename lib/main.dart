import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'chat_screen.dart';
import 'data.dart';
import 'firebase_options.dart';
import 'home_screen.dart';
import 'splash_screen.dart';
import 'welcome_screen.dart';

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
      darkTheme: ThemeData(
        colorSchemeSeed: _seed,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1020),
      ),
      themeMode: ThemeMode.dark,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const RootGate(),
    );
  }
}

enum _Stage { splash, welcome, auth, home, chat }

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  final _auth = AuthService();
  final _chat = ChatService();

  _Stage _stage = _Stage.splash;
  UserProfile? _me;
  Room? _room;
  bool _splashDone = false;
  bool _sessionChecked = false;

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
    _sessionChecked = true;
    _maybeLeaveSplash();
  }

  void _onSplashDone() {
    _splashDone = true;
    _maybeLeaveSplash();
  }

  void _maybeLeaveSplash() {
    if (!_splashDone || !_sessionChecked || !mounted) return;
    if (_stage != _Stage.splash) return;
    setState(() => _stage = _me != null ? _Stage.home : _Stage.welcome);
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _me = null;
      _room = null;
      _stage = _Stage.welcome;
    });
  }

  Widget _screen() {
    switch (_stage) {
      case _Stage.splash:
        return SplashScreen(key: const ValueKey('splash'), onDone: _onSplashDone);
      case _Stage.welcome:
        return WelcomeScreen(
          key: const ValueKey('welcome'),
          onStart: () => setState(() => _stage = _Stage.auth),
        );
      case _Stage.auth:
        return AuthScreen(
          key: const ValueKey('auth'),
          auth: _auth,
          onSignedIn: (profile) => setState(() {
            _me = profile;
            _stage = _Stage.home;
          }),
        );
      case _Stage.home:
        return HomeScreen(
          key: const ValueKey('home'),
          chat: _chat,
          me: _me!,
          onOpenRoom: (r) => setState(() {
            _room = r;
            _stage = _Stage.chat;
          }),
          onSignOut: _signOut,
        );
      case _Stage.chat:
        return ChatScreen(
          key: ValueKey('chat-${_room!.id}'),
          room: _room!,
          me: _me!,
          chat: _chat,
          onBack: () => setState(() {
            _room = null;
            _stage = _Stage.home;
          }),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      child: _screen(),
    );
  }
}
