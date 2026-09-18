// Telemetry model for the WHEP live-view HUD. Packets arrive as JSON text
// over the 'telemetry' WebRTC DataChannel (see whep_client.dart) — this
// file only parses/validates them; it never assumes the channel is
// reliable or ordered, so every packet is parsed independently and a
// malformed one is dropped rather than crashing the render loop.

/// Tracking state reported by the Vision pipeline for a given frame.
/// `unknown` is the safe fallback for any string the client doesn't
/// recognize yet, so a future/renamed state on the wire degrades to a
/// neutral HUD color instead of throwing.
enum TrackingState { tracking, coasting, fallCandidate, lost, unknown }

TrackingState _parseState(Object? raw) {
  switch (raw) {
    case 'TRACKING':
      return TrackingState.tracking;
    case 'COASTING':
      return TrackingState.coasting;
    case 'FALL_CANDIDATE':
      return TrackingState.fallCandidate;
    case 'LOST':
      return TrackingState.lost;
    default:
      return TrackingState.unknown;
  }
}

/// Normalized bounding box in `[0, 1]` fractions of the source frame —
/// deliberately not pixels, so the HUD painter can map it onto any
/// on-screen video rect (arbitrary aspect ratio, letterboxing, device
/// rotation) without the sender needing to know the viewer's geometry.
class NormalizedBBox {
  final double x;
  final double y;
  final double w;
  final double h;

  const NormalizedBBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  /// Returns null (rather than a garbage box) when the packet's bbox isn't
  /// a well-formed 4-element numeric array — a dropped/corrupt field
  /// should hide that rider's box for this frame, not draw a wrong one.
  static NormalizedBBox? tryParse(Object? raw) {
    if (raw is! List || raw.length != 4) return null;
    final values = <double>[];
    for (final v in raw) {
      if (v is num) {
        values.add(v.toDouble());
      } else {
        return null;
      }
    }
    return NormalizedBBox(
        x: values[0], y: values[1], w: values[2], h: values[3]);
  }
}

/// One tracked rider within a telemetry frame.
class RiderTrack {
  final String trackId;
  final double confidence;
  final NormalizedBBox bbox;

  const RiderTrack({
    required this.trackId,
    required this.confidence,
    required this.bbox,
  });

  static RiderTrack? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final bbox = NormalizedBBox.tryParse(raw['bbox']);
    if (bbox == null) return null;
    final trackId = raw['track_id'];
    final confidence = raw['confidence'];
    if (trackId is! String && trackId is! num) return null;
    if (confidence is! num) return null;
    return RiderTrack(
      trackId: trackId.toString(),
      confidence: confidence.toDouble().clamp(0.0, 1.0),
      bbox: bbox,
    );
  }
}

/// One decoded telemetry packet. `frameSeq` lets the HUD detect gaps/
/// out-of-order delivery (an unordered/unreliable DataChannel is a valid
/// configuration) without treating a gap as an error.
class TelemetryFrame {
  final int frameSeq;
  final TrackingState state;
  final List<RiderTrack> riders;

  const TelemetryFrame({
    required this.frameSeq,
    required this.state,
    required this.riders,
  });

  /// Parses one JSON telemetry packet. Returns null for anything that
  /// isn't a usable frame (malformed JSON, missing frame_seq, etc.) —
  /// callers treat null as "drop this packet", never as a thrown error,
  /// since a single bad/truncated packet on an unreliable channel is
  /// expected and must not take down the HUD.
  static TelemetryFrame? tryParse(Map<String, dynamic> json) {
    final frameSeq = json['frame_seq'];
    if (frameSeq is! num) return null;
    final riders = <RiderTrack>[];
    final rawRiders = json['riders'];
    if (rawRiders is List) {
      for (final r in rawRiders) {
        final track = RiderTrack.tryParse(r);
        if (track != null) riders.add(track);
      }
    }
    return TelemetryFrame(
      frameSeq: frameSeq.toInt(),
      state: _parseState(json['state']),
      riders: riders,
    );
  }
}
