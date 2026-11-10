import 'package:flutter/material.dart';

import 'countries.dart';
import 'data.dart';

/// Lets the user pick a country and type a number, then adds that person as a contact.
/// Pops with the added [UserProfile] so the caller can open the direct chat.
class AddContactSheet extends StatefulWidget {
  final ChatService chat;
  final UserProfile me;
  const AddContactSheet({super.key, required this.chat, required this.me});

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<AddContactSheet> {
  final _number = TextEditingController();
  Country? _country;
  UserProfile? _found;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  String get _fullPhone {
    final digits = _number.text.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
    return '+${_country!.dial}$digits';
  }

  Future<void> _search() async {
    if (_country == null) {
      setState(() => _error = 'اختار البلد أول');
      return;
    }
    if (_number.text.trim().isEmpty) {
      setState(() => _error = 'اكتب الرقم');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });
    try {
      final user = await widget.chat.findByPhone(_fullPhone);
      if (!mounted) return;
      if (user == null) {
        setState(() => _error = 'ما في حساب بهالرقم');
      } else if (user.uid == widget.me.uid) {
        setState(() => _error = 'هاد رقمك إنت');
      } else {
        setState(() => _found = user);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'صار خطأ بالبحث');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final user = _found;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await widget.chat.addContact(widget.me, user);
      if (mounted) Navigator.of(context).pop(user);
    } catch (e) {
      if (mounted) setState(() => _error = 'ما قدرنا نضيفه، جرّب مرة ثانية');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('إضافة صديق', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          DropdownButtonFormField<Country>(
            initialValue: _country,
            decoration: const InputDecoration(labelText: 'البلد (إجباري)'),
            items: [for (final c in countries) DropdownMenuItem(value: c, child: Text(c.label))],
            onChanged: (c) => setState(() {
              _country = c;
              _found = null;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'الرقم', hintText: 'بدون رمز البلد'),
            onChanged: (_) => setState(() {
              _found = null;
              _error = null;
            }),
          ),
          const SizedBox(height: 14),
          if (_found == null)
            FilledButton(
              onPressed: _busy ? null : _search,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('بحث'),
            )
          else
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(_found!.displayName.isNotEmpty ? _found!.displayName[0] : '?')),
                title: Text(_found!.displayName),
                subtitle: Text(_found!.fullPhone),
                trailing: FilledButton(
                  onPressed: _busy ? null : _add,
                  child: const Text('إضافة'),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}
