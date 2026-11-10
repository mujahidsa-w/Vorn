import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'add_contact_sheet.dart';
import 'call_screen.dart';
import 'call_service.dart';
import 'data.dart';

class HomeScreen extends StatefulWidget {
  final ChatService chat;
  final UserProfile me;
  final ValueChanged<Room> onOpenRoom;
  final VoidCallback onSignOut;

  const HomeScreen({
    super.key,
    required this.chat,
    required this.me,
    required this.onOpenRoom,
    required this.onSignOut,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _filter = 0; // 0 Chats, 1 Groups, 2 Calls

  StreamSubscription? _incomingSub;
  final Set<String> _handledCalls = {};

  @override
  void initState() {
    super.initState();
    _incomingSub = FirebaseFirestore.instance
        .collection('calls')
        .where('calleeId', isEqualTo: widget.me.uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final doc = change.doc;
        if (_handledCalls.contains(doc.id)) continue;
        _handledCalls.add(doc.id);
        // Ignore stale ringing calls (older than a minute).
        final created = (doc.data()?['createdAt'] as Timestamp?)?.toDate();
        if (created == null || DateTime.now().difference(created).inSeconds > 60) continue;
        _showIncoming(doc);
      }
    });
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }

  void _showIncoming(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!mounted) return;
    final d = doc.data()!;
    final controller = CallController(
      me: widget.me,
      other: UserProfile(
        uid: d['callerId'] as String? ?? '',
        displayName: d['callerName'] as String? ?? '',
      ),
      video: d['video'] as bool? ?? false,
    );
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(controller: controller, incomingDoc: doc),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            _chatsTab(),
            _contactsTab(),
            _comingSoon('Discover', Icons.explore_outlined),
            _settingsTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      floatingActionButton: _tab == 1
          ? FloatingActionButton(
              onPressed: _openAddContact,
              child: const Icon(Icons.person_add_alt_1_rounded),
            )
          : null,
    );
  }

  // ---------- Chats ----------
  Widget _chatsTab() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              const Text('Vexo', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton.filledTonal(onPressed: _openAddContact, icon: const Icon(Icons.person_add_alt_1_rounded)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              _chip(0, 'Chats', Icons.chat_bubble_rounded),
              _chip(1, 'Groups', Icons.groups_rounded),
              _chip(2, 'Calls', Icons.call_rounded),
            ],
          ),
        ),
        Expanded(
          child: _filter == 2
              ? _comingSoon('Calls', Icons.call_outlined)
              : StreamBuilder<List<Room>>(
                  stream: widget.chat.rooms(widget.me.uid),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(friendlyError(snap.error!), textAlign: TextAlign.center),
                        ),
                      );
                    }
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    var rooms = snap.data!;
                    if (_filter == 1) rooms = rooms.where((r) => !r.isDm).toList();
                    if (rooms.isEmpty) {
                      return Center(
                        child: Text('ما في محادثات بعد', style: TextStyle(color: scheme.onSurfaceVariant)),
                      );
                    }
                    return ListView.builder(
                      itemCount: rooms.length,
                      itemBuilder: (context, i) => _RoomTile(
                        title: rooms[i].titleFor(widget.me.uid),
                        subtitle: rooms[i].isDm ? 'محادثة خاصة' : rooms[i].game,
                        onTap: () => widget.onOpenRoom(rooms[i]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _chip(int index, String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _filter == index;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => setState(() => _filter = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: selected ? Colors.white : scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Contacts ----------
  Widget _contactsTab() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: const Text('Contacts', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('رقمك'),
            subtitle: Text(widget.me.fullPhone, textDirection: TextDirection.ltr),
            trailing: IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.me.fullPhone));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرقم')));
              },
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ContactEntry>>(
            stream: widget.chat.contacts(widget.me.uid),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!;
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    'ما في جهات اتصال بعد.\nاضغط زر الإضافة واختار البلد وأدخل الرقم.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                );
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  return _RoomTile(
                    title: c.displayName,
                    subtitle: c.fullPhone,
                    onTap: () => _openDm(UserProfile(uid: c.uid, displayName: c.displayName, fullPhone: c.fullPhone)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openAddContact() async {
    final added = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AddContactSheet(chat: widget.chat, me: widget.me),
    );
    if (added != null && mounted) {
      await _openDm(added);
    }
  }

  Future<void> _openDm(UserProfile other) async {
    try {
      final room = await widget.chat.openDm(widget.me, other);
      if (mounted) widget.onOpenRoom(room);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  // ---------- Misc ----------
  Widget _comingSoon(String title, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('قريباً', style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _settingsTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Settings', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          ListTile(
            leading: CircleAvatar(
              child: Text(widget.me.displayName.isNotEmpty ? widget.me.displayName[0] : '?'),
            ),
            title: Text(widget.me.displayName),
            subtitle: Text(widget.me.fullPhone, textDirection: TextDirection.ltr),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: widget.onSignOut, child: const Text('Sign out')),
          ),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _RoomTile({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                title.isNotEmpty ? title[0] : '?',
                style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
