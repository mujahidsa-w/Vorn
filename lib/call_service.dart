import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'data.dart';

const Map<String, dynamic> _rtcConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
  'sdpSemantics': 'unified-plan',
};

/// One audio or video call. Signaling (offer, answer, ICE) goes through Firestore.
/// Status values: ringing, connecting, connected, ended.
class CallController {
  final UserProfile me;
  final UserProfile other;
  final bool video;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final RTCVideoRenderer remote = RTCVideoRenderer();
  final RTCVideoRenderer localView = RTCVideoRenderer();
  final ValueNotifier<String> status = ValueNotifier('ringing');

  VoidCallback? onRemoteEnded;

  String? callId;
  RTCPeerConnection? _pc;
  MediaStream? _local;
  final List<StreamSubscription> _subs = [];
  final List<RTCIceCandidate> _queued = [];
  bool _remoteSet = false;
  bool _disposed = false;
  bool muted = false;

  CallController({required this.me, required this.other, required this.video});

  Future<void> init() async {
    await remote.initialize();
    await localView.initialize();
  }

  Future<void> _openMedia() async {
    // Browsers ask for mic and camera through getUserMedia on their own.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await [Permission.microphone, if (video) Permission.camera].request();
    }
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
    localView.srcObject = _local;
  }

  Future<RTCPeerConnection> _createPc() async {
    final pc = await createPeerConnection(_rtcConfig);
    for (final track in _local!.getTracks()) {
      await pc.addTrack(track, _local!);
    }
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) remote.srcObject = event.streams.first;
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        status.value = 'connected';
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        hangUp();
      }
    };
    return pc;
  }

  void _addCandidate(RTCIceCandidate c) {
    if (_remoteSet) {
      _pc?.addCandidate(c);
    } else {
      _queued.add(c);
    }
  }

  Future<void> _markRemoteSet() async {
    _remoteSet = true;
    for (final c in _queued) {
      await _pc?.addCandidate(c);
    }
    _queued.clear();
  }

  // ---------- Caller ----------
  Future<void> startCall() async {
    await _openMedia();
    final ref = _db.collection('calls').doc();
    callId = ref.id;
    _pc = await _createPc();
    _pc!.onIceCandidate = (c) => ref.collection('callerCandidates').add(c.toMap());

    final offer = await _pc!.createOffer({});
    await _pc!.setLocalDescription(offer);
    await ref.set({
      'callerId': me.uid,
      'callerName': me.displayName,
      'calleeId': other.uid,
      'calleeName': other.displayName,
      'video': video,
      'status': 'ringing',
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'createdAt': FieldValue.serverTimestamp(),
    });

    _subs.add(ref.snapshots().listen((snap) async {
      final d = snap.data();
      if (d == null) return;
      if (d['status'] == 'ended') {
        _remoteHungUp();
        return;
      }
      final answer = d['answer'] as Map<String, dynamic>?;
      if (answer != null && !_remoteSet && _pc != null) {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
        );
        status.value = 'connecting';
        await _markRemoteSet();
      }
    }));

    _subs.add(ref.collection('calleeCandidates').snapshots().listen((s) {
      for (final ch in s.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final c = ch.doc.data()!;
          _addCandidate(RTCIceCandidate(
            c['candidate'] as String?,
            c['sdpMid'] as String?,
            c['sdpMLineIndex'] as int?,
          ));
        }
      }
    }));
  }

  // ---------- Callee ----------
  Future<void> acceptCall(DocumentSnapshot<Map<String, dynamic>> incoming) async {
    callId = incoming.id;
    final d = incoming.data()!;
    final ref = _db.collection('calls').doc(callId);

    await _openMedia();
    _pc = await _createPc();
    _pc!.onIceCandidate = (c) => ref.collection('calleeCandidates').add(c.toMap());

    final offer = d['offer'] as Map<String, dynamic>;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
    );
    await _markRemoteSet();

    final answer = await _pc!.createAnswer({});
    await _pc!.setLocalDescription(answer);
    await ref.update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'status': 'active',
    });
    status.value = 'connecting';

    _subs.add(ref.collection('callerCandidates').snapshots().listen((s) {
      for (final ch in s.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final c = ch.doc.data()!;
          _addCandidate(RTCIceCandidate(
            c['candidate'] as String?,
            c['sdpMid'] as String?,
            c['sdpMLineIndex'] as int?,
          ));
        }
      }
    }));

    _subs.add(ref.snapshots().listen((snap) {
      if (snap.data()?['status'] == 'ended') _remoteHungUp();
    }));
  }

  Future<void> declineCall(DocumentSnapshot<Map<String, dynamic>> incoming) async {
    await _db.collection('calls').doc(incoming.id).update({'status': 'ended'});
    await dispose();
  }

  // ---------- Controls ----------
  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  Future<void> hangUp() async {
    final id = callId;
    if (id != null && !_disposed) {
      try {
        await _db.collection('calls').doc(id).update({'status': 'ended'});
      } catch (_) {}
    }
    await dispose();
  }

  void _remoteHungUp() {
    if (_disposed) return;
    final cb = onRemoteEnded;
    dispose().then((_) => cb?.call());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    status.value = 'ended';
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _pc?.close();
    _pc = null;
    for (final t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
    await remote.dispose();
    await localView.dispose();
  }
}
