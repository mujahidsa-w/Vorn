import 'package:flutter/material.dart';

import 'data.dart';

class RoomsScreen extends StatelessWidget {
  final ChatService chat;
  final ValueChanged<Room> onOpen;
  final VoidCallback onSignOut;

  const RoomsScreen({
    super.key,
    required this.chat,
    required this.onOpen,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الغرف'),
        actions: [
          TextButton(onPressed: onSignOut, child: const Text('خروج')),
        ],
      ),
      body: StreamBuilder<List<Room>>(
        stream: chat.rooms(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(friendlyError(snap.error!), textAlign: TextAlign.center),
            ));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rooms = snap.data!;
          if (rooms.isEmpty) {
            return const Center(child: Text('ما في غرف بعد'));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rooms.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final room = rooms[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(room.title.isNotEmpty ? room.title[0] : '?'),
                ),
                title: Text(room.title),
                subtitle: Text(room.game),
                onTap: () => onOpen(room),
              );
            },
          );
        },
      ),
    );
  }
}
