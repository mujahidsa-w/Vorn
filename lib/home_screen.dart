import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            _chatsTab(),
            _comingSoon('Contacts', Icons.people_outline),
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
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('إنشاء محادثة جديدة قريباً')),
              ),
              child: const Icon(Icons.edit_rounded),
            )
          : null,
    );
  }

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
              IconButton.filledTonal(onPressed: () {}, icon: const Icon(Icons.search)),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: () {}, icon: const Icon(Icons.add)),
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
                  stream: widget.chat.rooms(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(friendlyError(snap.error!), textAlign: TextAlign.center),
                      ));
                    }
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final rooms = snap.data!;
                    if (rooms.isEmpty) {
                      return Center(child: Text('ما في محادثات بعد', style: TextStyle(color: scheme.onSurfaceVariant)));
                    }
                    return ListView.builder(
                      itemCount: rooms.length,
                      itemBuilder: (context, i) => _RoomTile(
                        room: rooms[i],
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
            leading: CircleAvatar(child: Text(_initial(widget.me.displayName))),
            title: Text(widget.me.displayName),
            subtitle: const Text('حسابك'),
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

  String _initial(String s) => s.isNotEmpty ? s[0] : '?';
}

class _RoomTile extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  const _RoomTile({required this.room, required this.onTap});

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
                room.title.isNotEmpty ? room.title[0] : '?',
                style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(room.game, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
