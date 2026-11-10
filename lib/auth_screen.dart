import 'package:flutter/material.dart';

import 'data.dart';

class AuthScreen extends StatefulWidget {
  final AuthService auth;
  final ValueChanged<UserProfile> onSignedIn;

  const AuthScreen({super.key, required this.auth, required this.onSignedIn});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _user = TextEditingController();
  final _name = TextEditingController();
  final _pass = TextEditingController();

  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _name.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = _signUp
          ? await widget.auth.signUp(_user.text, _name.text, _pass.text)
          : await widget.auth.signIn(_user.text, _pass.text);
      if (!mounted) return;
      widget.onSignedIn(profile);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        colors: [scheme.primary, const Color(0xFF22D3EE)],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'V',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Vexo', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('شات الجيمرز', style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 28),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          if (_signUp) ...[
                            TextField(
                              controller: _name,
                              decoration: const InputDecoration(labelText: 'الاسم الظاهر'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: _user,
                            autocorrect: false,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(labelText: 'اسم المستخدم (إنجليزي)'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pass,
                            obscureText: true,
                            textDirection: TextDirection.ltr,
                            onSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(labelText: 'كلمة السر'),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(_signUp ? 'إنشاء حساب' : 'تسجيل الدخول'),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.error),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _signUp = !_signUp;
                      _error = null;
                    }),
                    child: Text(_signUp ? 'عندي حساب، سجّل دخول' : 'ما عندي حساب، سجّل جديد'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
