// Real WebRTC client. Per Connect_Master_Design_and_Build_Spec, real video
// uses authenticated WebRTC signalling via the Core (C-07) — sub-50ms
// negotiation target.
//
// SIGNALING CONTRACT, stated honestly (same posture as HttpPairingTransport
// and ControlChannelService's AUTH note): offer/answer/ICE candidates are
// exchanged as 'webrtc_offer' / 'webrtc_answer' / 'webrtc_ice' frames over
// the existing authenticated control-channel socket, rather than a second
// connection — see ControlChannelService.sendWebRtcSignal/webrtcSignals.
// This is this client's best-effort assumption, not something verified
// against a live Core — there isn't one to verify against yet (VIS-01
// unblocks that). What's real here is the client behavior: a genuine
// RTCPeerConnection, a real SDP offer/ICE gathering cycle, and a bounded
// timeout if the Core never answers — not a fabricated "connected" state.

import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'control_channel_service.dart';

enum WebRtcLinkStatus { idle, connecting, live, failed }

abstract class VideoRenderer {
  Future<void> attach(String streamId);
  Future<void> detach();
  bool get isAttached;

  /// Non-null only once a real remote video stream is actually rendering
  /// (see [WebRtcLinkStatus.live]) — SimulatedVideoRenderer never has one.
  RTCVideoRenderer? get liveRenderer => null;
}

class SimulatedVideoRenderer implements VideoRenderer {
  bool _attached = false;

  @override
  Future<void> attach(String streamId) async {
    _attached = true;
  }

  @override
  Future<void> detach() async {
    _attached = false;
  }

  @override
  bool get isAttached => _attached;

  @override
  RTCVideoRenderer? get liveRenderer => null;
}

/// Real PeerConnection lifecycle: creates an offer, gathers ICE candidates,
/// sends both over the control channel, and applies whatever answer/ICE
/// comes back. Succeeds only when a real remote video track actually
/// arrives — a bounded timeout with no track is a real failure, not a
/// silent hang or a fabricated "connected".
class RtcVideoRenderer implements VideoRenderer {
  final ControlChannelService control;
  final Duration answerTimeout;

  RtcVideoRenderer({required this.control, this.answerTimeout = const Duration(seconds: 10)});

  RTCPeerConnection? _pc;
  RTCVideoRenderer? _renderer;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _attached = false;

  @override
  bool get isAttached => _attached;
  @override
  RTCVideoRenderer? get liveRenderer => _renderer;

  @override
  Future<void> attach(String streamId) async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _renderer = renderer;

    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });
    _pc = pc;

    final trackArrived = Completer<void>();
    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
        if (!trackArrived.isCompleted) trackArrived.complete();
      }
    };
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;
      try {
        control.sendWebRtcSignal('webrtc_ice', {
          'device_id': streamId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      } on CommandRejected {
        // Link dropped mid-negotiation — the answer-timeout below is what
        // surfaces this as a real failure; a lost ICE candidate here isn't
        // itself fatal.
      }
    };

    _sub = control.webrtcSignals.listen((frame) async {
      final topic = frame['topic'];
      final payload = frame['payload'] as Map<String, dynamic>;
      if (topic == 'webrtc_answer') {
        await pc.setRemoteDescription(
          RTCSessionDescription(payload['sdp'] as String?, payload['type'] as String?),
        );
      } else if (topic == 'webrtc_ice' && payload['candidate'] != null) {
        await pc.addCandidate(RTCIceCandidate(
          payload['candidate'] as String?,
          payload['sdpMid'] as String?,
          payload['sdpMLineIndex'] as int?,
        ));
      }
    });

    // Receive-only: this app displays the Vision unit's stream, it never
    // sends its own camera.
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    control.sendWebRtcSignal('webrtc_offer', {
      'device_id': streamId,
      'sdp': offer.sdp,
      'type': offer.type,
    });
    _attached = true;

    await trackArrived.future.timeout(
      answerTimeout,
      onTimeout: () => throw TimeoutException(
          'No video from Core within ${answerTimeout.inSeconds}s'),
    );
  }

  @override
  Future<void> detach() async {
    await _sub?.cancel();
    _sub = null;
    await _pc?.close();
    _pc = null;
    await _renderer?.dispose();
    _renderer = null;
    _attached = false;
  }
}

class WebRtcService {
  final VideoRenderer renderer;
  WebRtcLinkStatus status = WebRtcLinkStatus.idle;
  String? failureReason;

  final _statusController = StreamController<void>.broadcast();
  Stream<void> get onStatusChange => _statusController.stream;

  WebRtcService({required this.renderer});

  Future<void> connectToVessel(String deviceId) async {
    if (status == WebRtcLinkStatus.connecting) return;
    status = WebRtcLinkStatus.connecting;
    failureReason = null;
    _statusController.add(null);
    try {
      await renderer.attach(deviceId);
      status = WebRtcLinkStatus.live;
    } catch (e) {
      status = WebRtcLinkStatus.failed;
      failureReason = e.toString();
    }
    _statusController.add(null);
  }

  Future<void> disconnect() async {
    await renderer.detach();
    status = WebRtcLinkStatus.idle;
    failureReason = null;
    _statusController.add(null);
  }

  /// Fire-and-forget: this is teardown, not a state transition anything is
  /// still listening for, so cleanup doesn't wait for detach() to finish
  /// before closing the (now pointless) status stream.
  void dispose() {
    renderer.detach();
    _statusController.close();
  }
}
