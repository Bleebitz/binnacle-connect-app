// Abstract interface over WebRTC so eptz_video_view.dart never depends on
// a concrete plugin. Per Connect_Master_Design_and_Build_Spec, real video
// uses authenticated WebRTC signalling via the Core (C-07) — sub-50ms
// negotiation target.
//
// TODO(hardware): wire this to flutter_webrtc once Vision hardware exists
// (VIS-01 unblocked) and the Core's signalling endpoint is defined. Adding
// the real dependency now would make this scaffold require native iOS/
// Android WebRTC toolchains to even build, which is the wrong tradeoff
// before there is a camera to connect to.

abstract class VideoRenderer {
  Future<void> attach(String streamId);
  Future<void> detach();
  bool get isAttached;
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
}

class WebRtcService {
  final VideoRenderer renderer;
  WebRtcService({VideoRenderer? renderer}) : renderer = renderer ?? SimulatedVideoRenderer();

  Future<void> connectToVessel(String deviceId) => renderer.attach(deviceId);
  Future<void> disconnect() => renderer.detach();
}
