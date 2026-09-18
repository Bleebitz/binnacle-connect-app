// Storage management: real local delete (distinct from a nonexistent
// "delete from cloud"), confirmation before a destructive delete, and
// never claiming remote storage without a real upload confirmation.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/media_import_service.dart';
import 'package:binnacle_connect/core/services/media_upload_service.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/screens/storage_screen.dart';
import 'package:binnacle_connect/ui/theme/binnacle_theme.dart';

import 'support/fake_media_services.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('deleteLocalCopy removes both the library entry and the real file', () async {
    final connectivity = FakeConnectivityChecker();
    final uploader = NoOpMediaUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    final importer = FakeMediaImportService();
    final clip = await repo.importPicked(
      const PickedMedia(kind: ImportMediaKind.photo, sourcePath: '/x', fileName: 'a.jpg', sizeBytes: 10),
      importer: importer,
    );
    expect(File(clip.localPath!).existsSync(), isTrue);

    repo.deleteLocalCopy(clip.id);

    expect(repo.clips, isEmpty);
    expect(File(clip.localPath!).existsSync(), isFalse);
  });

  test('deleting an entry that shares a file with another entry keeps the file', () async {
    final repo = ClipRepository(connectivity: FakeConnectivityChecker(), uploader: NoOpMediaUploadService());
    await repo.hydrate();
    final src = await repo.importPicked(
      const PickedMedia(kind: ImportMediaKind.video, sourcePath: '/x', fileName: 'a.mp4', sizeBytes: 10),
      importer: FakeMediaImportService(),
    );
    repo.addEditedClip(Clip(
      id: 'edit-legacy',
      title: 'legacy edit',
      duration: const Duration(seconds: 1),
      kind: ClipKind.highlight,
      riderId: 'r0',
      capturedAt: DateTime(2026),
      uploadStatus: UploadStatus.onPhoneOnly,
      localPath: src.localPath, // pre-export edits shared the source file
    ));
    repo.deleteLocalCopy('edit-legacy');
    expect(File(src.localPath!).existsSync(), isTrue, reason: 'the source clip still uses this file');
    expect(repo.clips.map((c) => c.id), [src.id]);
  });

  testWidgets('Storage screen shows a confirmation before deleting, and cancelling keeps the media',
      (tester) async {
    final connectivity = FakeConnectivityChecker();
    final uploader = NoOpMediaUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    final importer = FakeMediaImportService();
    await repo.importPicked(
      const PickedMedia(kind: ImportMediaKind.video, sourcePath: '/x', fileName: 'a.mp4', sizeBytes: 2048),
      importer: importer,
    );

    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<ClipRepository>.value(value: repo)],
      child: MaterialApp(theme: BinnacleTheme.dark(), home: const StorageScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Confirmed stored remotely'), findsOneWidget);
    expect(find.textContaining('None — no cloud backend exists yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete local copy?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.clips, hasLength(1), reason: 'cancelling the confirmation must not delete anything');
  });
}
