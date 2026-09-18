// Domain models for Connect Live — the multi-destination cloud broadcast
// control surface approved in "Binnacle Connect Cloud, Live & Subscription
// Architecture v0.1" (BIN-38). See §5 and §18 for the exact per-destination
// lifecycle and health-field list this file mirrors.
//
// NOTHING HERE TALKS TO A NETWORK. This file is pure data — see
// live_broadcast_service.dart for the injectable transport boundary that
// will eventually talk to a real Binnacle Cloud control plane. No cloud
// endpoint, OAuth flow, or billing behavior is implemented or assumed here.

/// Per-destination (and per-ingest) lifecycle. Matches architecture §18
/// exactly: a button press is not proof of anything past [requested] — every
/// later state requires an authoritative update from Core/cloud.
enum BroadcastLifecycleState {
  requested,
  connecting,
  live,
  degraded,
  failed,
  stopped,
  unknown,
}

extension BroadcastLifecycleStateX on BroadcastLifecycleState {
  /// True only for states an authoritative source confirmed as actually
  /// carrying video right now. [requested]/[connecting] are pending;
  /// [degraded] still counts as "up" per §5 (a broadcast can be live and
  /// degraded at once — dropped frames, not disconnection).
  bool get isUp => this == BroadcastLifecycleState.live || this == BroadcastLifecycleState.degraded;

  String get label => switch (this) {
        BroadcastLifecycleState.requested => 'Requested',
        BroadcastLifecycleState.connecting => 'Connecting',
        BroadcastLifecycleState.live => 'Live',
        BroadcastLifecycleState.degraded => 'Degraded',
        BroadcastLifecycleState.failed => 'Failed',
        BroadcastLifecycleState.stopped => 'Stopped',
        BroadcastLifecycleState.unknown => 'Unknown',
      };
}

/// Destination classes approved in architecture §2.2/§14. Only
/// [binnacleLive] and [customRtmp] can go live without a third-party OAuth
/// session this app does not implement (see ConnectedServicesService) —
/// youtube/facebook/twitch require a Connected Services link first.
enum DestinationKind { binnacleLive, youtube, facebook, twitch, customRtmp }

extension DestinationKindX on DestinationKind {
  String get label => switch (this) {
        DestinationKind.binnacleLive => 'Binnacle Live',
        DestinationKind.youtube => 'YouTube',
        DestinationKind.facebook => 'Facebook',
        DestinationKind.twitch => 'Twitch',
        DestinationKind.customRtmp => 'Custom RTMP/RTMPS',
      };

  /// Whether this destination needs a linked third-party account before it
  /// can be selected — see ConnectedServicesService. Binnacle Live is
  /// Binnacle's own service; custom RTMP is a URL/key the user supplies
  /// directly. Neither needs OAuth.
  bool get requiresConnectedService =>
      this == DestinationKind.youtube || this == DestinationKind.facebook || this == DestinationKind.twitch;
}

/// A destination the user has selected/configured for one broadcast
/// attempt. [customEndpoint]/[customStreamKey] are populated only for
/// [DestinationKind.customRtmp], entered directly by the user — never
/// invented by this app, never a fabricated provider credential.
class BroadcastDestination {
  final DestinationKind kind;
  final String? customEndpoint;
  final String? customStreamKey;

  const BroadcastDestination({required this.kind, this.customEndpoint, this.customStreamKey});

  String get label =>
      kind == DestinationKind.customRtmp && customEndpoint != null ? 'Custom: $customEndpoint' : kind.label;

  @override
  bool operator ==(Object other) =>
      other is BroadcastDestination &&
      other.kind == kind &&
      other.customEndpoint == customEndpoint &&
      other.customStreamKey == customStreamKey;

  @override
  int get hashCode => Object.hash(kind, customEndpoint, customStreamKey);
}

/// The outgoing view sent to every destination of one broadcast — §3.
/// Raw camera, Track Follow and any future AI-directed view are DISTINCT
/// concepts (§3: "must never present a generated or inferred view as an
/// unmodified camera view") — this enum, not a boolean, is what keeps that
/// distinction typed rather than stringly-typed.
enum OutgoingView { rawCamera, trackFollow, wide, closeFollow, automaticDirector, cleanOutput }

extension OutgoingViewX on OutgoingView {
  /// §3's INITIAL required choices are Raw Camera and Track Follow only.
  /// Wide/Close Follow/Automatic Director/Clean Output are the explicitly
  /// named future extension point — present as typed values so a later
  /// change is additive, but not selectable yet: no encoder support exists
  /// to honor them truthfully.
  bool get isAvailableNow => this == OutgoingView.rawCamera || this == OutgoingView.trackFollow;

  String get label => switch (this) {
        OutgoingView.rawCamera => 'Raw Camera',
        OutgoingView.trackFollow => 'Track Follow',
        OutgoingView.wide => 'Wide',
        OutgoingView.closeFollow => 'Close Follow',
        OutgoingView.automaticDirector => 'Automatic Director',
        OutgoingView.cleanOutput => 'Clean Output',
      };

  String get description => switch (this) {
        OutgoingView.rawCamera => 'Unmodified camera feed.',
        OutgoingView.trackFollow => 'Track-guided reframing on the tracked rider.',
        OutgoingView.wide => 'Coming soon.',
        OutgoingView.closeFollow => 'Coming soon.',
        OutgoingView.automaticDirector => 'Coming soon.',
        OutgoingView.cleanOutput => 'Coming soon.',
      };
}

/// Authoritative health for one destination — §5's exact field list:
/// state, bitrate, output quality, drop/degradation indicator, and
/// freshness (via [asOf]). [reason] carries a rejection/failure explanation
/// when the Core/cloud provided one; never fabricated by this client.
class DestinationHealth {
  final BroadcastDestination destination;
  final BroadcastLifecycleState state;
  final int? bitrateKbps;
  final String? outputQuality;
  final bool degraded;
  final String? reason;
  final DateTime asOf;

  const DestinationHealth({
    required this.destination,
    required this.state,
    required this.asOf,
    this.bitrateKbps,
    this.outputQuality,
    this.degraded = false,
    this.reason,
  });

  DestinationHealth copyWith({
    BroadcastLifecycleState? state,
    int? bitrateKbps,
    String? outputQuality,
    bool? degraded,
    String? reason,
    DateTime? asOf,
  }) =>
      DestinationHealth(
        destination: destination,
        state: state ?? this.state,
        bitrateKbps: bitrateKbps ?? this.bitrateKbps,
        outputQuality: outputQuality ?? this.outputQuality,
        degraded: degraded ?? this.degraded,
        reason: reason ?? this.reason,
        asOf: asOf ?? this.asOf,
      );

  static DestinationHealth unknown(BroadcastDestination destination, DateTime asOf) =>
      DestinationHealth(destination: destination, state: BroadcastLifecycleState.unknown, asOf: asOf);

  /// State freshness — §5's "last authoritative update." A destination that
  /// hasn't heard from Core/cloud in a while must not keep showing as live
  /// just because it once was; see LiveBroadcastService's staleness sweep.
  bool isStale(DateTime now, {Duration threshold = const Duration(seconds: 20)}) =>
      now.difference(asOf) > threshold;
}

/// One GO LIVE attempt/session, per architecture §2.1/§18. [ingestState] is
/// Binnacle Cloud's own uplink state (§5) — distinct from any individual
/// destination, since a healthy uplink can still fan out to a mix of
/// live/failed destinations (§18: "If YouTube is live but Twitch failed,
/// Connect must show that exact mixed state").
class LiveBroadcastSession {
  final String id;
  final OutgoingView view;
  final DateTime requestedAt;
  final BroadcastLifecycleState ingestState;
  final Map<DestinationKind, DestinationHealth> destinations;
  final DateTime? liveSince;
  final DateTime asOf;

  const LiveBroadcastSession({
    required this.id,
    required this.view,
    required this.requestedAt,
    required this.ingestState,
    required this.destinations,
    required this.asOf,
    this.liveSince,
  });

  /// Duration is never derived from wall-clock-since-button-press — only
  /// from [liveSince], which is set exactly once, the first time any
  /// destination is authoritatively reported live (§18/§5).
  Duration? get duration => liveSince == null ? null : asOf.difference(liveSince!);

  bool get anyDestinationUp => destinations.values.any((d) => d.state.isUp);

  bool get isTerminal =>
      ingestState == BroadcastLifecycleState.stopped ||
      (ingestState == BroadcastLifecycleState.failed &&
          destinations.values.every((d) =>
              d.state == BroadcastLifecycleState.failed || d.state == BroadcastLifecycleState.stopped));

  LiveBroadcastSession withIngest(BroadcastLifecycleState state, {DateTime? asOf}) {
    final ts = asOf ?? DateTime.now();
    return LiveBroadcastSession(
      id: id,
      view: view,
      requestedAt: requestedAt,
      ingestState: state,
      destinations: destinations,
      liveSince: liveSince ?? (state == BroadcastLifecycleState.live ? ts : null),
      asOf: ts,
    );
  }

  LiveBroadcastSession withDestination(DestinationHealth health) {
    final map = Map<DestinationKind, DestinationHealth>.from(destinations);
    map[health.destination.kind] = health;
    return LiveBroadcastSession(
      id: id,
      view: view,
      requestedAt: requestedAt,
      ingestState: ingestState,
      destinations: map,
      liveSince: liveSince ?? (health.state == BroadcastLifecycleState.live ? health.asOf : null),
      asOf: DateTime.now(),
    );
  }
}
