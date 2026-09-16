// Core media catalog — fetches the list of clips a Core actually has,
// each with a real media URL for playback/download/share. Same honesty
// posture as HttpPairingTransport: this is this client's best-effort
// assumption about the endpoint shape, not something verified against a
// live Core — there isn't one yet. What's real is the client behavior: a
// genuine HTTPS GET, real timeout/error handling, and real JSON parsing
// into Clip.fromJson — not a fabricated catalog.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/clip.dart';
import '../app_config.dart';

enum CatalogOutcome { success, unreachable, unauthorized, malformed }

class CatalogResult {
  final CatalogOutcome outcome;
  final List<Clip> clips;
  final String? message;
  const CatalogResult({required this.outcome, this.clips = const [], this.message});
}

abstract class MediaCatalogService {
  Future<CatalogResult> fetchClips(String deviceId, {required String bearerToken});
}

/// Demo mode's catalog: there is no media server to ask, so this always
/// reports an empty, successful catalog — consistent with NoOpPairingTransport
/// never opening a socket in demo mode.
class NoOpMediaCatalogService implements MediaCatalogService {
  @override
  Future<CatalogResult> fetchClips(String deviceId, {required String bearerToken}) async =>
      const CatalogResult(outcome: CatalogOutcome.success, clips: []);
}

/// ENDPOINT CONTRACT, stated honestly: GET https://<coreHost>/spotter/
/// {deviceId}/clips, bearer-authenticated, mirroring the pairing endpoint's
/// path shape. Returns a JSON array of clip objects (see Clip.fromJson for
/// the expected fields). This path and shape are this client's best-effort
/// assumption, not something verified against a live Core.
class HttpMediaCatalogService implements MediaCatalogService {
  final http.Client _client;
  final Duration timeout;

  HttpMediaCatalogService({http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();

  @override
  Future<CatalogResult> fetchClips(String deviceId, {required String bearerToken}) async {
    final uri = Uri.parse('${AppConfig.coreUrl}/spotter/$deviceId/clips');
    http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'authorization': 'Bearer $bearerToken'})
          .timeout(timeout);
    } on TimeoutException {
      return const CatalogResult(
          outcome: CatalogOutcome.unreachable, message: 'Timed out reaching the Core.');
    } catch (_) {
      return const CatalogResult(
          outcome: CatalogOutcome.unreachable, message: 'Could not reach the Core.');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return const CatalogResult(outcome: CatalogOutcome.unauthorized);
    }
    if (response.statusCode != 200) {
      return CatalogResult(
        outcome: CatalogOutcome.malformed,
        message: 'The Core returned an unexpected status (${response.statusCode}).',
      );
    }
    try {
      final body = jsonDecode(response.body);
      if (body is! List) throw const FormatException('expected a JSON array');
      final clips = body
          .whereType<Map<String, dynamic>>()
          .map(Clip.fromJson)
          .toList(growable: false);
      return CatalogResult(outcome: CatalogOutcome.success, clips: clips);
    } on FormatException {
      return const CatalogResult(
        outcome: CatalogOutcome.malformed,
        message: 'The Core sent back a catalog this app could not understand.',
      );
    }
  }
}
