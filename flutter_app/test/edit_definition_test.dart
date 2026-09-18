// Pure-logic coverage for EditDefinition (highlight editor metadata) —
// serialization round-trip and the honest "never mutates the source, no
// re-encoded file" invariants that Clip/ClipRepository rely on. The
// editor screen's video pipeline itself (VideoPlayerController,
// video_thumbnail) needs a real device/codec to exercise meaningfully —
// see the device evidence doc for that verification instead of an
// automated widget test, which would need to fake a real video decoder.

import 'package:flutter_test/flutter_test.dart';

import 'package:binnacle_connect/core/models/clip.dart';

void main() {
  test('EditDefinition round-trips through JSON exactly', () {
    const original = EditDefinition(
      sourceClipId: 'clip-1',
      trimStart: Duration(seconds: 2),
      trimEnd: Duration(seconds: 12),
      aspect: CropAspect.portrait,
      cropOffsetX: 0.25,
      cropOffsetY: -0.1,
      coverFrameAt: Duration(seconds: 5),
    );
    final restored = EditDefinition.tryFromJson(original.toJson())!;
    expect(restored.sourceClipId, original.sourceClipId);
    expect(restored.trimStart, original.trimStart);
    expect(restored.trimEnd, original.trimEnd);
    expect(restored.aspect, original.aspect);
    expect(restored.cropOffsetX, original.cropOffsetX);
    expect(restored.cropOffsetY, original.cropOffsetY);
    expect(restored.coverFrameAt, original.coverFrameAt);
  });

  test('a malformed edit_definition (missing source id) is dropped, not thrown', () {
    expect(EditDefinition.tryFromJson({'trim_start_ms': 100}), isNull);
    expect(EditDefinition.tryFromJson(null), isNull);
  });

  test('an unrecognized aspect string degrades to original rather than throwing', () {
    final restored = EditDefinition.tryFromJson({
      'source_clip_id': 'clip-1',
      'aspect': 'ultrawide-panorama',
      'trim_start_ms': 0,
      'trim_end_ms': 1000,
      'cover_frame_at_ms': 0,
    });
    expect(restored!.aspect, CropAspect.original);
  });

  test('an edited Clip carries the edit definition through toJson/fromLocalJson', () {
    final edited = Clip(
      id: 'edit-1',
      title: 'Edited',
      duration: const Duration(seconds: 10),
      kind: ClipKind.highlight,
      riderId: 'me',
      capturedAt: DateTime(2026, 1, 1),
      localPath: '/tmp/original.mp4',
      editDefinition: const EditDefinition(
        sourceClipId: 'source-1',
        trimStart: Duration(seconds: 1),
        trimEnd: Duration(seconds: 9),
        aspect: CropAspect.square,
        coverFrameAt: Duration(seconds: 3),
      ),
    );
    final restored = Clip.fromLocalJson(edited.toJson());
    expect(restored.editDefinition, isNotNull);
    expect(restored.editDefinition!.sourceClipId, 'source-1');
    expect(restored.editDefinition!.aspect, CropAspect.square);
    // The restored clip's own local file is the same path as the
    // original — this is the "shares the same file, never mutates or
    // deletes the source" contract stated in the editor's module comment.
    expect(restored.localPath, edited.localPath);
  });
}
