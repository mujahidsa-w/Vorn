import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_service.dart';

class CallScreen extends StatefulWidget {
  final CallController controller;
  final bool outgoing;
  final DocumentSnapshot<Map<String, dynamic>>? incomingDoc;

  const CallScreen({
    super.key,
    required this.controller,
    this.outgoing = false,
    this.incomingDoc,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallController get c => widget.controller;
  bool _accepted = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    c.onRemoteEnded = () {
      if (mounted) Navigator.of(context).maybePop();
    };
    _start();
  }

  Future<void> _start() async {
    await c.init();
    if (!mounted) return;
    setState(() {});
    if (widget.outgoing) await c.startCall();
  }

  @override
  void dispose() {
    c.onRemoteEnded = null;
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _accepted = true);
    await c.acceptCall(widget.incomingDoc!);
  }

  Future<void> _decline() async {
    await c.declineCall(widget.incomingDoc!);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _end() async {
    await c.hangUp();
    if (mounted) Navigator.of(context).maybePop();
  }

  String _label(String s) {
    switch (s) {
      case 'ringing':
        return widget.incomingDoc != null ? 'مكالمة واردة...' : 'يرن...';
      case 'connecting':
        return 'جاري الاتصال...';
      case 'connected':
        return 'متصل';
      default:
        return 'انتهت المكالمة';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingRinging = widget.incomingDoc != null && !_accepted;

    return Scaffold(
      backgroundColor: const Color(0xFF050B1F),
      body: SafeArea(
        child: ValueListenableBuilder<String>(
          valueListenable: c.status,
          builder: (context, status, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                if (c.video && status == 'connected')
                  RTCVideoView(c.remote, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                else
                  _avatarBackdrop(),
                if (c.video)
                  Positioned(
                    top: 16,
                    right: 16,
                    width: 110,
                    height: 150,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: RTCVideoView(c.localView, mirror: true),
                    ),
                  ),
                Positioned(
                  top: 60,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        isIncomingRinging ? c.other.displayName : c.other.displayName,
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(_label(status), style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 36,
                  left: 0,
                  right: 0,
                  child: isIncomingRinging ? _incomingControls() : _callControls(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _avatarBackdrop() {
    final initial = c.other.displayName.isNotEmpty ? c.other.displayName[0] : '?';
    return Center(
      child: CircleAvatar(
        radius: 70,
        backgroundColor: const Color(0xFF1E6BFF),
        child: Text(initial, style: const TextStyle(fontSize: 56, color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _callControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundButton(
          icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          color: Colors.white24,
          onTap: () {
            c.toggleMute();
            setState(() => _muted = c.muted);
          },
        ),
        _roundButton(icon: Icons.call_end_rounded, color: const Color(0xFFE53935), onTap: _end, size: 72),
      ],
    );
  }

  Widget _incomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundButton(icon: Icons.call_end_rounded, color: const Color(0xFFE53935), onTap: _decline, size: 72),
        _roundButton(icon: Icons.call_rounded, color: const Color(0xFF22C55E), onTap: _accept, size: 72),
      ],
    );
  }

  Widget _roundButton({required IconData icon, required Color color, required VoidCallback onTap, double size = 60}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }
}
