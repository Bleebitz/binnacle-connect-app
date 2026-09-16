// Unit tests for ClipRepository.loadFromCore — proves the repository
// actually replaces its clip list from a real (mocked-transport) catalog
// fetch, surfaces a real error instead of silently staying empty, and only
// attempts once until an explicit retry (see main.dart's idempotent-guard
// trigger, which this mirrors: attemptedLoad prevents re-fetching a
// genuinely empty catalog on every rebuild).

import 'package:flutter_test/flutter_test.dart';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/media_catalog_service.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';

class _FakeCatalog implements MediaCatalogService {
  final CatalogResult result;
  int callCount = 0;
  _FakeCatalog(this.result);

  @override
  Future<CatalogResult> fetchClips(String deviceId, {required String bearerToken}) async {
    callCount++;
    return result;
  }
}

void main() {
  test('loadFromCore replaces the clip list on success', () async {
    final clip = Clip(
      id: 'c1',
      title: 'Real clip',
      duration: const Duration(seconds: 5),
      kind: ClipKind.highlight,
      riderId: 'levi',
      capturedAt: DateTime.now(),
      mediaUrl: 'https://core.example/media/c1.mp4',
    );
    final repo = ClipRepository();
    final catalog = _FakeCatalog(CatalogResult(outcome: CatalogOutcome.success, clips: [clip]));

    await repo.loadFromCore(catalog, 'vision-0001', bearerToken: 'tok');

    expect(repo.clips, hasLength(1));
    expect(repo.clips.first.id, 'c1');
    expect(repo.loading, isFalse);
    expect(repo.loadError, isNull);
    expect(repo.attemptedLoad, isTrue);
  });

  test('loadFromCore surfaces a real error instead of silently staying empty', () async {
    final repo = ClipRepository();
    final catalog = _FakeCatalog(
      const CatalogResult(outcome: CatalogOutcome.unreachable, message: 'Could not reach the Core.'),
    );

    await repo.loadFromCore(catalog, 'vision-0001', bearerToken: 'tok');

    expect(repo.clips, isEmpty);
    expect(repo.loadError, 'Could not reach the Core.');
    expect(repo.attemptedLoad, isTrue);
  });

  test('retryLoadFromCore resets attemptedLoad and fetches again', () async {
    final repo = ClipRepository();
    final catalog = _FakeCatalog(
      const CatalogResult(outcome: CatalogOutcome.unreachable, message: 'nope'),
    );
    await repo.loadFromCore(catalog, 'vision-0001', bearerToken: 'tok');
    expect(catalog.callCount, 1);

    repo.retryLoadFromCore(catalog, 'vision-0001', bearerToken: 'tok');
    for (var i = 0; i < 100 && catalog.callCount < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(catalog.callCount, 2);
  });
}
