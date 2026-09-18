// Thin real wrapper around connectivity_plus, so the offline upload
// queue (ClipRepository) depends on a small interface instead of the
// concrete plugin class directly — the same reasoning as every other
// injectable boundary in this app (MediaUploadService, PairingTransport,
// etc.): production gets the real plugin, tests get a trivial fake with
// no platform channel involved at all.

import 'package:connectivity_plus/connectivity_plus.dart';

export 'package:connectivity_plus/connectivity_plus.dart' show ConnectivityResult;

abstract class ConnectivityChecker {
  Future<List<ConnectivityResult>> check();
  Stream<List<ConnectivityResult>> get onChanged;
}

class RealConnectivityChecker implements ConnectivityChecker {
  final Connectivity _connectivity = Connectivity();

  @override
  Future<List<ConnectivityResult>> check() => _connectivity.checkConnectivity();

  @override
  Stream<List<ConnectivityResult>> get onChanged => _connectivity.onConnectivityChanged;
}
