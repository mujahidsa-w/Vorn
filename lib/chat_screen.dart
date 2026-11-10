import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'call_screen.dart';
import 'call_service.dart';
import 'data.dart';

const _mineColor = Color(0xFF1E6BFF);
const _theirColor = Color(0xFF232838);
const _composerColor = Color(0xFF161B2B);

class ChatScreen extends StatefulWidget {
  final Room room;
  final UserProfile me;
  final ChatService chat;
  final VoidCallback onBack;

  const ChatScreen({
    super.key,
    required this.room,
    required this.me,
    required this.chat,
    required this.onBack,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  bool _recording = false;
  int _recSeconds = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _input.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  UserProfile? get _otherUser {
    if (!widget.room.isDm) return null;
    final otherUid = widget.room.members.firstWhere((m) => m != widget.me.uid, orElse: () => '');
    if (otherUid.isEmpty) return null;
    return UserProfile(uid: otherUid, displayName: widget.room.titleFor(widget.me.uid));
  }

  void _startCall({required bool video}) {
    final other = _otherUser;
    if (other == null) return;
    final controller = CallController(me: widget.me, other: other, video: video);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(controller: controller, outgoing: true),
      ),
    );
  }

  void _showAttachments() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 12,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('صورة من المعرض'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      await widget.chat.sendImage(widget.room.id, widget.me, picked.path);
    } catch (e) {
      _showMessage('ما قدرنا نرسل الصورة');
    }
  }

  void _showEmojiPicker() {
    const emojis = [
      '😀', '😂', '😍', '😎', '😭', '😡', '👍', '👏', '🙏', '🔥',
      '❤️', '🎉', '😅', '🤔', '👀', '💯', '🎮', '🏆', '👋', '🤝',
      '😴', '🥳', '😱', '🙌', '✅',
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 7,
          padding: const EdgeInsets.all(12),
          children: [
            for (final e in emojis)
              InkWell(
                onTap: () {
                  _input.text = _input.text + e;
                  _input.selection = TextSelection.collapsed(offset: _input.text.length);
                  Navigator.pop(ctx);
                },
                child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
              ),
          ],
        ),
      ),
    );
  }

  /// Shows "Online" when the other user was active in the last 3 minutes, otherwise the last-seen time.
  Widget _subtitleWidget(String fallback) {
    final other = _otherUser;
    if (other == null) {
      return Text(fallback, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.white60));
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(other.uid).snapshots(),
      builder: (context, snap) {
        final seen = (snap.data?.data()?['lastSeen'] as Timestamp?)?.toDate();
        final online = seen != null && DateTime.now().difference(seen).inMinutes < 3;
        final text = online
            ? 'Online'
            : seen == null
                ? fallback
                : 'آخر ظهور ${TimeOfDay.fromDateTime(seen).format(context)}';
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: online ? const Color(0xFF4ADE80) : Colors.white60),
        );
      },
    );
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      await widget.chat.sendText(widget.room.id, widget.me, text);
    } catch (e) {
      _showMessage('ما قدرنا نرسل الرسالة');
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _showMessage('لازم تسمح بالمايك لتسجيل الصوت');
        return;
      }
      // On web the recorder ignores the path and returns a blob URL on stop.
      var path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        RecordConfig(
          encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: kIsWeb ? 22050 : 44100,
          numChannels: 1,
        ),
        path: path,
      );
      _stopwatch
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recSeconds = _stopwatch.elapsed.inSeconds);
      });
      if (mounted) setState(() => _recording = true);
    } catch (e) {
      _showMessage('ما قدرنا نبدأ التسجيل');
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_recording) return;
    _ticker?.cancel();
    _stopwatch.stop();
    final seconds = _stopwatch.elapsed.inSeconds;
    if (mounted) setState(() => _recording = false);
    final path = await _recorder.stop();
    if (!send || path == null || seconds < 1) return;
    try {
      await widget.chat.sendAudio(
        widget.room.id,
        widget.me,
        path,
        seconds,
        mime: kIsWeb ? 'audio/wav' : 'audio/mp4',
        ext: kIsWeb ? 'wav' : 'm4a',
      );
    } catch (e) {
      _showMessage('ما قدرنا نرسل الرسالة الصوتية');
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.room.titleFor(widget.me.uid);
    final subtitle = widget.room.isDm ? 'محادثة خاصة' : widget.room.game;
    final initial = title.isNotEmpty ? title[0] : '?';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: BackButton(onPressed: widget.onBack),
        title: Row(
          children: [
            CircleAvatar(radius: 19, child: Text(initial)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  _subtitleWidget(subtitle),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (widget.room.isDm) ...[
            IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () => _startCall(video: true)),
            IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => _startCall(video: false)),
          ],
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: widget.chat.messages(widget.room.id),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('خطأ بتحميل الرسائل'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final messages = snap.data!;
                _scrollToEnd();
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return _Bubble(
                      key: ValueKey(m.id),
                      message: m,
                      mine: m.senderId == widget.me.uid,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: _recording ? _recordingBar() : _composer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return Row(
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: _mineColor,
              child: IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: _showAttachments,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 6, right: 4),
                decoration: BoxDecoration(
                  color: _composerColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.emoji_emotions_outlined, color: scheme.onSurfaceVariant),
                      onPressed: _showEmojiPicker,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (hasText)
              CircleAvatar(
                radius: 23,
                backgroundColor: _mineColor,
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: _sendText,
                ),
              )
            else
              // Hold to record, release to send.
              GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopRecording(send: true),
                child: const CircleAvatar(
                  radius: 23,
                  backgroundColor: _mineColor,
                  child: Icon(Icons.mic_rounded, color: Colors.white),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _recordingBar() {
    final m = _recSeconds ~/ 60;
    final s = (_recSeconds % 60).toString().padLeft(2, '0');
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1620),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Color(0xFFFF5C7A), size: 14),
          const SizedBox(width: 8),
          Text('$m:$s', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          const Text('أفلت للإرسال', style: TextStyle(color: Colors.white70)),
          const SizedBox(width: 12),
          GestureDetector(
            onLongPressEnd: (_) => _stopRecording(send: true),
            onLongPressUp: () => _stopRecording(send: true),
            child: const CircleAvatar(
              radius: 20,
              backgroundColor: _mineColor,
              child: Icon(Icons.mic_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;

  const _Bubble({super.key, required this.message, required this.mine});

  String _time(BuildContext context) {
    final t = message.createdAt;
    if (t == null) return '';
    return TimeOfDay.fromDateTime(t).format(context);
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.72;
    final content = message.isAudio
        ? _VoiceContent(message: message, mine: mine)
        : message.isImage
            ? _ImageContent(url: message.mediaUrl)
        : Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35));

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
      decoration: BoxDecoration(
        color: mine ? _mineColor : _theirColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(_time(context), style: const TextStyle(fontSize: 11, color: Colors.white70)),
              if (mine) ...[
                const SizedBox(width: 3),
                const Icon(Icons.done_all_rounded, size: 14, color: Colors.white70),
              ],
            ],
          ),
        ],
      ),
    );

    if (mine) {
      return Align(alignment: AlignmentDirectional.centerEnd, child: bubble);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        CircleAvatar(
          radius: 15,
          child: Text(message.senderName.isNotEmpty ? message.senderName[0] : '?', style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 6),
        Flexible(child: bubble),
      ],
    );
  }
}

class _VoiceContent extends StatefulWidget {
  final ChatMessage message;
  final bool mine;
  const _VoiceContent({required this.message, required this.mine});

  @override
  State<_VoiceContent> createState() => _VoiceContentState();
}

class _VoiceContentState extends State<_VoiceContent> {
  final _player = AudioPlayer();
  StreamSubscription? _sub;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _sub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
    } else {
      await _player.play(UrlSource(widget.message.audioUrl));
      if (mounted) setState(() => _playing = true);
    }
  }

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final seed = widget.message.id.codeUnits.fold<int>(0, (a, b) => a + b);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.mine ? Colors.white : _mineColor,
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: widget.mine ? _mineColor : Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(22, (i) {
            final h = 6.0 + ((seed + i * 37) % 18);
            return Container(
              width: 3,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.white70,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
        const SizedBox(width: 8),
        Text(_fmt(widget.message.duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

class _ImageContent extends StatelessWidget {
  final String url;
  const _ImageContent({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: 220,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const SizedBox(width: 220, height: 160, child: Center(child: CircularProgressIndicator())),
        errorBuilder: (context, error, stack) =>
            const SizedBox(width: 220, height: 80, child: Center(child: Text('تعذّر تحميل الصورة'))),
      ),
    );
  }
}
