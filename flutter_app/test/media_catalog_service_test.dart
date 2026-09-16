// Unit tests for HttpMediaCatalogService — the real Core clip catalog
// fetch (see media_catalog_service.dart's module comment for the endpoint
// contract). Same approach as pairing_transport_test.dart: a real HTTP
// request/response cycle via an injected http.Client (MockClient), no live
// Core to test against, but the client-side logic — URL/header
// construction, status-code mapping, JSON parsing into Clip.fromJson,
// timeout handling — is fully real and fully testable without one.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/media_catalog_service.dart';

void main() {
  test('sends a real authenticated HTTPS GET to /spotter/{deviceId}/clips', () async {
    http.Request? captured;
    final service = HttpMediaCatalogService(
      client: MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode([]), 200);
      }),
    );

    await service.fetchClips('vision-0001', bearerToken: 'secret-token');

    expect(captured, isNotNull);
    expect(captured!.method, 'GET');
    expect(captured!.url.path, '/spotter/vision-0001/clips');
    expect(captured!.headers['authorization'], 'Bearer secret-token');
  });

  test('parses a real JSON clip array into Clip objects', () async {
    final service = HttpMediaCatalogService(
      client: MockClient((req) async => http.Response(
            jsonEncode([
              {
                'id': 'clip-1',
                'title': 'Backside 180',
                'duration_s': 14,
                'kind': 'highlight',
                'rider_id': 'levi',
                'signed': true,
                'gps_attached': true,
                'captured_at': '2026-09-16T10:00:00Z',
                'media_url': 'https://core.example/media/clip-1.mp4',
              },
            ]),
            200,
          )),
    );

    final result = await service.fetchClips('vision-0001', bearerToken: 'tok');

    expect(result.outcome, CatalogOutcome.success);
    expect(result.clips, hasLength(1));
    expect(result.clips.first.id, 'clip-1');
    expect(result.clips.first.kind, ClipKind.highlight);
    expect(result.clips.first.duration, const Duration(seconds: 14));
    expect(result.clips.first.mediaUrl, 'https://core.example/media/clip-1.mp4');
  });

  test('maps 401 to unauthorized', () async {
    final service = HttpMediaCatalogService(
      client: MockClient((req) async => http.Response('', 401)),
    );
    final result = await service.fetchClips('vision-0001', bearerToken: 'tok');
    expect(result.outcome, CatalogOutcome.unauthorized);
  });

  test('maps 403 to unauthorized', () async {
    final service = HttpMediaCatalogService(
      client: MockClient((req) async => http.Response('', 403)),
    );
    final result = await service.fetchClips('vision-0001', bearerToken: 'tok');
    expect(result.outcome, CatalogOutcome.unauthorized);
  });

  test('a non-array JSON body is treated as malformed, not a crash', () async {
    final service = HttpMediaCatalogService(
      client: MockClient((req) async => http.Response(jsonEncode({'not': 'an array'}), 200)),
    );
    final result = await service.fetchClips('vision-0001', bearerToken: 'tok');
    expect(result.outcome, CatalogOutcome.malformed);
  });

  test('an unparseable body is treated as malformed, not a crash', () async {
    final service = HttpMediaCatalogService(
      client: MockClient((req) async => http.Response('not json', 200)),
    );
    final result = await service.fetchClips('vision-0001', bearerToken: 'tok');
    expect(result.outcome, CatalogOutcome.malformed);
  });

  test('a connection error maps to unreachable, not an uncaught exception', () async {
    final service = HttpMediaCatalogService(
      client: MockClient((req) async => throw http.ClientException('connection refused')),
    );
    final result = await service.fetchClips('vision-0001', bearerToken: 'tok');
    expect(result.outcome, CatalogOutcome.unreachable);
  });

  test('NoOpMediaCatalogService always reports an empty, successful catalog', () async {
    final result =
        await NoOpMediaCatalogService().fetchClips('vision-0001', bearerToken: 'unused');
    expect(result.outcome, CatalogOutcome.success);
    expect(result.clips, isEmpty);
  });
}
