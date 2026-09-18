// Connected Services — architecture §14. Reports which external broadcast
// destinations this device has linked, and lets the user add a custom
// RTMP/RTMPS target directly (a URL/key THEY supply, not a fabricated
// provider credential).
//
// WHAT THIS DELIBERATELY DOES NOT DO: implement OAuth for YouTube/Facebook/
// Twitch. §14 requires that "OAuth tokens, stream keys and provider
// credentials must not be stored in plaintext on the phone" and that "the
// cloud control plane should securely store and rotate provider
// authorization" — neither a real OAuth flow nor a cloud control plane
// exists yet, so those three providers are honestly reported as not
// connected, with no fake "Connect" button that pretends to succeed.

import 'package:flutter/foundation.dart';

import '../models/live_broadcast.dart';

class ConnectedServiceStatus {
  final DestinationKind kind;
  final bool connected;
  final String? accountLabel; // e.g. a channel name — never fabricated
  const ConnectedServiceStatus({required this.kind, required this.connected, this.accountLabel});
}

abstract class ConnectedServicesService extends ChangeNotifier {
  List<ConnectedServiceStatus> get statuses;
  List<BroadcastDestination> get customDestinations;

  void addCustomDestination({required String endpoint, required String streamKey});
  void removeCustomDestination(BroadcastDestination destination);
}

/// The only implementation shipped. YouTube/Facebook/Twitch always report
/// not-connected — see module comment. Custom RTMP/RTMPS is real,
/// session-only, in-memory: the user's own endpoint/key, held only in this
/// object for this app session, never written to disk, never logged (see
/// LiveBroadcastService, which never logs a destination's stream key).
class LocalConnectedServicesService extends ConnectedServicesService {
  final List<BroadcastDestination> _custom = [];

  @override
  List<ConnectedServiceStatus> get statuses => const [
        ConnectedServiceStatus(kind: DestinationKind.youtube, connected: false),
        ConnectedServiceStatus(kind: DestinationKind.facebook, connected: false),
        ConnectedServiceStatus(kind: DestinationKind.twitch, connected: false),
      ];

  @override
  List<BroadcastDestination> get customDestinations => List.unmodifiable(_custom);

  @override
  void addCustomDestination({required String endpoint, required String streamKey}) {
    _custom.add(BroadcastDestination(
      kind: DestinationKind.customRtmp,
      customEndpoint: endpoint,
      customStreamKey: streamKey,
    ));
    notifyListeners();
  }

  @override
  void removeCustomDestination(BroadcastDestination destination) {
    _custom.removeWhere((d) => d == destination);
    notifyListeners();
  }
}
