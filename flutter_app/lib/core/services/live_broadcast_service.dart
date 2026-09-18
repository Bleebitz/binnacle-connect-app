// Connect Live control surface (BIN-38) — the injectable service/transport
// boundary between the UI and a future real Binnacle Cloud control plane.
// Per architecture §18: a button press is never proof of anything. This
// service only ever reports [BroadcastLifecycleState.requested] locally;
// every later state comes from an authoritative [BroadcastUpdate] the
// transport received, real or (in demo mode) deterministically simulated
// and clearly labeled as such.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/live_broadcast.dart';
import 'command_result.dart';
import 'control_channel_service.dart';
import 'entitlement_service.dart';

/// One authoritative push about a session in progress — either the shared
/// cloud ingest state, or one destination's health. Real transports
/// translate whatever wire message they receive into one of these; nothing
/// in this file constructs one to fabricate progress.
sealed class BroadcastUpdate {
  const BroadcastUpdate();
}

class IngestUpdate extends BroadcastUpdate {
  final BroadcastLifecycleState state;
  final DateTime asOf;
  const IngestUpdate(this.state, this.asOf);
}

class DestinationUpdate extends BroadcastUpdate {
  final DestinationHealth health;
  const DestinationUpdate(this.health);
}

/// Injectable boundary for future Core/cloud integration. [requestGoLive]/
/// [requestStop] only ever confirm that a REQUEST was accepted — see
/// [CommandResult] — never that anything is live. Authoritative lifecycle
/// changes arrive exclusively through [updates].
abstract class BroadcastTransport {
  Future<CommandResult> requestGoLive({
    required OutgoingView view,
    required List<BroadcastDestination> destinations,
  });
  Future<CommandResult> requestStop();
  Stream<BroadcastUpdate> get updates;
  void dispose();
}

/// Demo mode's transport: a deterministic, clearly-simulated lifecycle —
/// never random, so tests and the person watching can both rely on exact
/// timing. Ingest connects first, then each destination in the order it was
/// requested, mirroring the real fan-out ordering in architecture §4.1
/// (one uplink, then per-destination distribution) without ever claiming
/// Core/cloud verification. See LiveBroadcastService.demo for the visible
/// "SIMULATED" labeling this feeds.
class DemoBroadcastTransport implements BroadcastTransport {
  final _controller = StreamController<BroadcastUpdate>.broadcast();
  final List<Timer> _timers = [];
  bool _disposed = false;

  @override
  Stream<BroadcastUpdate> get updates => _controller.stream;

  @override
  Future<CommandResult> requestGoLive({
    required OutgoingView view,
    required List<BroadcastDestination> destinations,
  }) async {
    await Future.delayed(const Duration(milliseconds: 120));
    if (_disposed) return const CommandResult(CommandOutcome.disconnected);
    _controller.add(IngestUpdate(BroadcastLifecycleState.connecting, DateTime.now()));
    _timers.add(Timer(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      _controller.add(IngestUpdate(BroadcastLifecycleState.live, DateTime.now()));
      for (var i = 0; i < destinations.length; i++) {
        final destination = destinations[i];
        _controller.add(DestinationUpdate(DestinationHealth(
          destination: destination,
          state: BroadcastLifecycleState.connecting,
          asOf: DateTime.now(),
        )));
        _timers.add(Timer(Duration(milliseconds: 250 + i * 200), () {
          if (_disposed) return;
          _controller.add(DestinationUpdate(DestinationHealth(
            destination: destination,
            state: BroadcastLifecycleState.live,
            asOf: DateTime.now(),
            bitrateKbps: 4200,
            outputQuality: '1080p60',
          )));
        }));
      }
    }));
    return const CommandResult(CommandOutcome.acknowledged);
  }

  @override
  Future<CommandResult> requestStop() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (_disposed) return const CommandResult(CommandOutcome.disconnected);
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _controller.add(IngestUpdate(BroadcastLifecycleState.stopped, DateTime.now()));
    return const CommandResult(CommandOutcome.acknowledged);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _controller.close();
  }
}

/// Real transport: reuses the ONE authenticated Core control socket that
/// already exists (see ControlChannelService) rather than opening a second
/// connection to an invented cloud endpoint — the same pattern already used
/// for WebRTC signaling (control.sendWebRtcSignal).
///
/// WIRE CONTRACT, stated honestly: 'request_live_broadcast'/
/// 'stop_live_broadcast' commands through the existing ack pipeline, and a
/// 'live_broadcast_state' topic pushed back (see control_channel_service's
/// _onMessage). This is this client's best-effort shape, unverified against
/// a real Core/cloud — none exists yet. No Core currently implements this
/// topic, so a real request will time out rather than fabricate progress:
/// that is the correct, honest behavior BIN-38 requires ("Core mode showing
/// Unknown before authoritative state"), not a bug to paper over.
class CoreBroadcastTransport implements BroadcastTransport {
  final ControlChannelService control;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final _controller = StreamController<BroadcastUpdate>.broadcast();

  CoreBroadcastTransport({required this.control}) {
    _sub = control.liveBroadcastUpdates.listen(_onWirePayload);
  }

  @override
  Stream<BroadcastUpdate> get updates => _controller.stream;

  void _onWirePayload(Map<String, dynamic> payload) {
    final scope = payload['scope'];
    final asOf = DateTime.tryParse(payload['as_of'] as String? ?? '') ?? DateTime.now();
    final state = _parseState(payload['state'] as String?);
    if (scope == 'ingest') {
      _controller.add(IngestUpdate(state, asOf));
    } else if (scope == 'destination') {
      final kind = _parseKind(payload['destination'] as String?);
      if (kind == null) return; // fail closed: unknown destination name, ignore rather than guess
      _controller.add(DestinationUpdate(DestinationHealth(
        destination: BroadcastDestination(kind: kind),
        state: state,
        asOf: asOf,
        bitrateKbps: payload['bitrate_kbps'] as int?,
        outputQuality: payload['output_quality'] as String?,
        degraded: payload['degraded'] == true,
        reason: payload['reason'] as String?,
      )));
    }
  }

  static BroadcastLifecycleState _parseState(String? s) => switch (s) {
        'requested' => BroadcastLifecycleState.requested,
        'connecting' => BroadcastLifecycleState.connecting,
        'live' => BroadcastLifecycleState.live,
        'degraded' => BroadcastLifecycleState.degraded,
        'failed' => BroadcastLifecycleState.failed,
        'stopped' => BroadcastLifecycleState.stopped,
        _ => BroadcastLifecycleState.unknown, // fail closed: never guess "live" from an unrecognized string
      };

  static DestinationKind? _parseKind(String? s) => switch (s) {
        'binnacleLive' => DestinationKind.binnacleLive,
        'youtube' => DestinationKind.youtube,
        'facebook' => DestinationKind.facebook,
        'twitch' => DestinationKind.twitch,
        'customRtmp' => DestinationKind.customRtmp,
        _ => null,
      };

  @override
  Future<CommandResult> requestGoLive({
    required OutgoingView view,
    required List<BroadcastDestination> destinations,
  }) async {
    // sendConfirmed() throws CommandRejected SYNCHRONOUSLY (not as a Future
    // rejection — see control_channel_service.dart's sendCommand) for an
    // unpaired/wrong-role/offline caller. BroadcastTransport's contract is
    // that every outcome, including a same-tick rejection, arrives as a
    // CommandResult — never an uncaught exception the UI has to guess about.
    try {
      return await control.sendConfirmed('request_live_broadcast', {
        'view': view.name,
        'destinations': destinations
            .map((d) => {
                  'kind': d.kind.name,
                  if (d.customEndpoint != null) 'endpoint': d.customEndpoint,
                  if (d.customStreamKey != null) 'stream_key': d.customStreamKey,
                })
            .toList(),
      });
    } on CommandRejected {
      return const CommandResult(CommandOutcome.rejected);
    }
  }

  @override
  Future<CommandResult> requestStop() async {
    try {
      return await control.sendConfirmed('stop_live_broadcast', {});
    } on CommandRejected {
      return const CommandResult(CommandOutcome.rejected);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}

/// Owns the current [LiveBroadcastSession] and applies every authoritative
/// update to it. Never mutates lifecycle state except in direct response to
/// an update from [BroadcastTransport] — see [goLive]/[stop] for the two
/// narrow exceptions ([BroadcastLifecycleState.requested] locally, and
/// folding a rejection/timeout/disconnect into [BroadcastLifecycleState.
/// failed] so the UI has something to show instead of hanging forever).
class LiveBroadcastService extends ChangeNotifier {
  final BroadcastTransport transport;
  final bool demo;

  LiveBroadcastService({required this.transport, this.demo = false}) {
    _sub = transport.updates.listen(_apply);
    _staleSweeper = Timer.periodic(const Duration(seconds: 5), (_) => _sweepStale());
  }

  StreamSubscription<BroadcastUpdate>? _sub;
  Timer? _staleSweeper;
  bool _disposed = false;

  LiveBroadcastSession? session;

  /// True strictly between a GO LIVE/STOP tap and the transport's ack/
  /// rejection/timeout — "pending," per BIN-38's required behavior, never
  /// used to imply success.
  bool busy = false;
  String? lastError;

  bool get isLive => session?.anyDestinationUp ?? false;

  Future<bool> goLive({
    required OutgoingView view,
    required List<BroadcastDestination> destinations,
    required LiveEntitlement entitlement,
  }) async {
    if (busy) return false;
    if (destinations.isEmpty) {
      lastError = 'Choose at least one destination.';
      notifyListeners();
      return false;
    }
    if (destinations.length > entitlement.maxSimultaneousDestinations) {
      lastError = entitlement.maxSimultaneousDestinations == 1
          ? 'Free plan supports one live destination at a time.'
          : '${entitlement.tier.label} plan supports up to ${entitlement.maxSimultaneousDestinations} '
              'destinations at once.';
      notifyListeners();
      return false;
    }
    if (!view.isAvailableNow) {
      lastError = '${view.label} is not available yet.';
      notifyListeners();
      return false;
    }

    busy = true;
    lastError = null;
    final now = DateTime.now();
    session = LiveBroadcastSession(
      id: 'live-${now.microsecondsSinceEpoch}',
      view: view,
      requestedAt: now,
      ingestState: BroadcastLifecycleState.requested,
      destinations: {
        for (final destination in destinations)
          destination.kind: DestinationHealth(destination: destination, state: BroadcastLifecycleState.requested, asOf: now),
      },
      asOf: now,
    );
    notifyListeners();

    final result = await transport.requestGoLive(view: view, destinations: destinations);
    if (_disposed) return false;
    busy = false;
    if (result.outcome != CommandOutcome.acknowledged) {
      final reason = switch (result.outcome) {
        CommandOutcome.rejected => 'The Core rejected this broadcast request.',
        CommandOutcome.timedOut =>
          'No response from Core/cloud — the live-broadcast contract is not confirmed yet.',
        CommandOutcome.disconnected => 'Lost connection before the broadcast request was confirmed.',
        CommandOutcome.acknowledged => null,
      };
      lastError = reason;
      var failed = session?.withIngest(BroadcastLifecycleState.failed);
      // The request itself never reached "connecting" for any destination —
      // every one of them must show failed too, not linger at "Requested"
      // while ingest already says Failed (§18's mixed-state honesty cuts
      // both ways: a state must never look better OR more ambiguous than
      // what actually happened).
      if (failed != null) {
        for (final health in failed.destinations.values) {
          failed = failed!.withDestination(health.copyWith(state: BroadcastLifecycleState.failed, reason: reason));
        }
      }
      session = failed;
      notifyListeners();
      return false;
    }
    // Acknowledged only means Core/cloud accepted the REQUEST (§18) — not
    // that anything is live. Only _apply(), fed by an authoritative
    // BroadcastUpdate, can ever move a destination to live/degraded.
    session = session?.withIngest(BroadcastLifecycleState.connecting);
    notifyListeners();
    return true;
  }

  Future<void> stop() async {
    if (session == null || busy) return;
    busy = true;
    notifyListeners();
    final result = await transport.requestStop();
    if (_disposed) return;
    busy = false;
    if (result.outcome == CommandOutcome.acknowledged) {
      session = session?.withIngest(BroadcastLifecycleState.stopped);
    } else {
      lastError = 'Stop not confirmed (${result.outcome.name}) — the broadcast may still be live.';
    }
    notifyListeners();
  }

  void _apply(BroadcastUpdate update) {
    if (session == null) return;
    if (update is IngestUpdate) {
      session = session!.withIngest(update.state, asOf: update.asOf);
    } else if (update is DestinationUpdate) {
      session = session!.withDestination(update.health);
    }
    notifyListeners();
  }

  /// A destination that stops hearing from Core/cloud must not keep
  /// reporting live/degraded just because it once did — degrades to
  /// [BroadcastLifecycleState.unknown] per §5's freshness requirement.
  void _sweepStale() {
    final current = session;
    if (current == null) return;
    final now = DateTime.now();
    var next = current;
    for (final health in current.destinations.values) {
      if (health.state.isUp && health.isStale(now)) {
        next = next.withDestination(health.copyWith(state: BroadcastLifecycleState.unknown));
      }
    }
    if (next != current) {
      session = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _staleSweeper?.cancel();
    transport.dispose();
    super.dispose();
  }
}
