// Fakes for the local Demo media path. They use synchronous file I/O only:
// async dart:io hangs under the widget-test FakeAsync zone.

import 'dart:io';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/control_channel_service.dart';
import 'package:binnacle_connect/core/services/demo_media.dart';

/// Writes a small non-empty file where a real extractor would write a JPEG,
/// and records what it was asked for.
class FakeFrameExtractor implements FrameExtractor {
  final List<({String asset, Duration position, String out})> requests = [];
  final List<String> exported = [];
  Object? failWith;
  bool writeEmptyFile = false;
  String? galleryUri = 'content://media/external/images/media/1';

  @override
  Future<ExtractedFrame> extractFrame({
    required String assetPath,
    required Duration position,
    required String outputPath,
  }) async {
    requests.add((asset: assetPath, position: position, out: outputPath));
    final err = failWith;
    if (err != null) throw err;
    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
        writeEmptyFile ? const [] : const [0xFF, 0xD8, 0xFF, 0xD9]);
    return ExtractedFrame(path: outputPath, width: 1920, height: 1080);
  }

  @override
  Future<String?> exportToGallery(
      {required String path, required String displayName}) async {
    exported.add(displayName);
    return galleryUri;
  }
}

/// In-memory stand-in for the persisted Demo Library.
class FakeDemoLibraryStore implements DemoLibraryStore {
  List<Clip> saved = [];
  int saves = 0;

  @override
  Future<List<Clip>> load() async => List.of(saved);

  @override
  Future<void> save(List<Clip> clips) async {
    saved = List.of(clips);
    saves++;
  }
}

/// Records every command the app tries to send to a Core (sendConfirmed and
/// the nudge/snapshot/highlight helpers all go through sendCommand). In Demo
/// Mode the local media actions must produce none.
class RecordingControlChannelService extends ControlChannelService {
  final List<String> commands = [];

  RecordingControlChannelService() : super(demo: true);

  @override
  String sendCommand(String command, Map<String, dynamic> params,
      {String? actor}) {
    commands.add(command);
    return super.sendCommand(command, params, actor: actor);
  }
}
