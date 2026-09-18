// Basic highlight editor: trim start/end, choose a cover frame, choose a
// crop/framing aspect with an adjustable offset, preview, and save as a
// separate edited copy.
//
// WHAT "SAVE" ACTUALLY PRODUCES, stated plainly: a new, distinct Clip
// that shares the *same* underlying video file as the source (never
// mutates or deletes the original) plus an [EditDefinition] — trim/crop/
// cover-frame parameters applied for real at playback (seek-to-start,
// stop-at-end, a real Transform/ClipRect sized to the chosen aspect),
// not a separately re-encoded video file. Real re-encoding would need
// either a GPL-licensed FFmpeg build (a real commercial-licensing
// problem for this closed-source app) or non-trivial native
// MediaMuxer/AVAssetExportSession platform work — both out of scope for
// this first version. See clip.dart's EditDefinition doc comment for the
// same statement in the data model itself.
//
// The cover frame IS a real, separately-extracted JPEG (via
// video_thumbnail — a real platform thumbnail API, not GPL/FFmpeg), used
// as the edited clip's thumbnailPath.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

import '../../core/models/clip.dart';
import '../theme/binnacle_theme.dart';
import 'library_screen.dart' show ClipRepository;

extension on CropAspect {
  String get label => switch (this) {
        CropAspect.original => 'Original',
        CropAspect.portrait => 'Portrait',
        CropAspect.landscape => 'Landscape',
        CropAspect.square => 'Square',
      };

  /// null means "use the source video's own aspect ratio."
  double? ratio(double sourceAspect) => switch (this) {
        CropAspect.original => null,
        CropAspect.portrait => 9 / 16,
        CropAspect.landscape => 16 / 9,
        CropAspect.square => 1.0,
      };
}

class HighlightEditorScreen extends StatefulWidget {
  final Clip sourceClip;
  const HighlightEditorScreen({super.key, required this.sourceClip});

  @override
  State<HighlightEditorScreen> createState() => _HighlightEditorScreenState();
}

class _HighlightEditorScreenState extends State<HighlightEditorScreen> {
  VideoPlayerController? _player;
  String? _loadError;

  double _trimStartFraction = 0;
  double _trimEndFraction = 1;
  double _coverFrameFraction = 0;
  CropAspect _aspect = CropAspect.original;
  double _cropOffsetX = 0;
  double _cropOffsetY = 0;

  bool _exporting = false;
  String? _exportError;
  bool _cancelExport = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.sourceClip.localPath;
    if (path == null) {
      setState(() => _loadError = 'No local video file for this clip.');
      return;
    }
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _player = controller);
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Could not open this video: $e');
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Duration get _fullDuration => _player?.value.duration ?? Duration.zero;
  Duration get _trimStart => _fullDuration * _trimStartFraction;
  Duration get _trimEnd => _fullDuration * _trimEndFraction;
  Duration get _coverFrameAt => _fullDuration * _coverFrameFraction;

  Future<void> _previewAt(Duration position) async {
    final player = _player;
    if (player == null) return;
    await player.pause();
    await player.seekTo(position);
  }

  Future<void> _save() async {
    final player = _player;
    final path = widget.sourceClip.localPath;
    if (player == null || path == null) return;
    setState(() {
      _exporting = true;
      _exportError = null;
      _cancelExport = false;
    });

    String? coverPath;
    try {
      // Real frame extraction (not a re-encode) — video_thumbnail calls
      // the platform's own thumbnail API (MediaMetadataRetriever on
      // Android, AVAssetImageGenerator on iOS), no GPL dependency.
      coverPath = await vt.VideoThumbnail.thumbnailFile(
        video: path,
        timeMs: _coverFrameAt.inMilliseconds,
        imageFormat: vt.ImageFormat.JPEG,
        quality: 80,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportError = 'Could not generate a cover frame: $e';
        });
      }
      return;
    }

    if (_cancelExport) {
      setState(() => _exporting = false);
      return;
    }

    final sourceAspect = player.value.aspectRatio;
    final edited = Clip(
      id: 'edit-${DateTime.now().microsecondsSinceEpoch}',
      title: '${widget.sourceClip.title} (edited)',
      duration: _trimEnd - _trimStart,
      thumbnailPath: coverPath,
      kind: widget.sourceClip.kind,
      riderId: widget.sourceClip.riderId,
      capturedAt: widget.sourceClip.capturedAt,
      localPath: path, // same file — see module comment
      uploadStatus: UploadStatus.onPhoneOnly,
      signed: false,
      gpsAttached: false,
      sizeBytes: widget.sourceClip.sizeBytes,
    );
    final editedWithDefinition = _attachEditDefinition(edited, sourceAspect);

    if (!mounted) return;
    context.read<ClipRepository>().addEditedClip(editedWithDefinition);
    setState(() => _exporting = false);
    Navigator.of(context).pop(editedWithDefinition);
  }

  Clip _attachEditDefinition(Clip base, double sourceAspect) {
    // Clip has no public copyWith for editDefinition (it's set once at
    // construction, immutable after) — build the final Clip directly.
    return Clip(
      id: base.id,
      title: base.title,
      duration: base.duration,
      thumbnailPath: base.thumbnailPath,
      kind: base.kind,
      riderId: base.riderId,
      capturedAt: base.capturedAt,
      localPath: base.localPath,
      uploadStatus: base.uploadStatus,
      signed: base.signed,
      gpsAttached: base.gpsAttached,
      sizeBytes: base.sizeBytes,
      editDefinition: EditDefinition(
        sourceClipId: widget.sourceClip.id,
        trimStart: _trimStart,
        trimEnd: _trimEnd,
        aspect: _aspect,
        cropOffsetX: _cropOffsetX,
        cropOffsetY: _cropOffsetY,
        coverFrameAt: _coverFrameAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BinnacleColors.navyDeep,
      appBar: AppBar(title: const Text('Edit highlight')),
      body: SafeArea(
        child: _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_loadError!, style: const TextStyle(color: BinnacleColors.orange)),
                ),
              )
            : _player == null
                ? const Center(child: CircularProgressIndicator())
                : _buildEditor(),
      ),
    );
  }

  Widget _buildEditor() {
    final player = _player!;
    final sourceAspect = player.value.aspectRatio;
    final targetAspect = _aspect.ratio(sourceAspect) ?? sourceAspect;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AspectRatio(
          aspectRatio: sourceAspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(player),
              // Real crop preview overlay — dims everything outside the
              // chosen aspect/offset so what you see is what gets applied
              // at playback (see the module comment: this is enforced for
              // real at playback, not just a cosmetic preview).
              _CropOverlay(
                sourceAspect: sourceAspect,
                targetAspect: targetAspect,
                offsetX: _cropOffsetX,
                offsetY: _cropOffsetY,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          IconButton(
            icon: Icon(player.value.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => setState(() {
              if (player.value.isPlaying) {
                player.pause();
              } else {
                _previewAt(_trimStart).then((_) => player.play());
              }
            }),
          ),
          const Text('Preview trim range', style: TextStyle(color: BinnacleColors.slateLight, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        const Text('Trim', style: TextStyle(fontWeight: FontWeight.w600)),
        RangeSlider(
          values: RangeValues(_trimStartFraction, _trimEndFraction),
          onChanged: (values) {
            setState(() {
              _trimStartFraction = values.start;
              _trimEndFraction = values.end;
            });
            _previewAt(_fullDuration * values.start);
          },
        ),
        Text(
          '${_fmt(_trimStart)} – ${_fmt(_trimEnd)} (${_fmt(_trimEnd - _trimStart)})',
          style: BinnacleTheme.mono(size: 11, color: BinnacleColors.slateLight),
        ),
        const SizedBox(height: 16),
        const Text('Cover frame', style: TextStyle(fontWeight: FontWeight.w600)),
        Slider(
          value: _coverFrameFraction.clamp(0, 1),
          onChanged: (v) {
            setState(() => _coverFrameFraction = v);
            _previewAt(_fullDuration * v);
          },
        ),
        Text(_fmt(_coverFrameAt), style: BinnacleTheme.mono(size: 11, color: BinnacleColors.slateLight)),
        const SizedBox(height: 16),
        const Text('Framing', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final aspect in CropAspect.values)
              ChoiceChip(
                label: Text(aspect.label),
                selected: _aspect == aspect,
                onSelected: (_) => setState(() => _aspect = aspect),
              ),
          ],
        ),
        if (_aspect != CropAspect.original) ...[
          const SizedBox(height: 12),
          Text('Crop position', style: BinnacleTheme.mono(size: 11, color: BinnacleColors.slateLight)),
          Slider(
            value: _cropOffsetX,
            min: -0.5,
            max: 0.5,
            onChanged: (v) => setState(() => _cropOffsetX = v),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'Trim and framing are preserved originals, applied at playback — not yet a '
          'separately re-encoded video file.',
          style: TextStyle(color: BinnacleColors.slateDim, fontSize: 11, height: 1.4),
        ),
        if (_exportError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_exportError!, style: const TextStyle(color: BinnacleColors.orange, fontSize: 12)),
          ),
        const SizedBox(height: 16),
        if (_exporting)
          Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            const Text('Saving…'),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _cancelExport = true),
              child: const Text('Cancel'),
            ),
          ])
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('Save as edited copy')),
          ),
      ],
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _CropOverlay extends StatelessWidget {
  final double sourceAspect;
  final double targetAspect;
  final double offsetX;
  final double offsetY;
  const _CropOverlay({
    required this.sourceAspect,
    required this.targetAspect,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  Widget build(BuildContext context) {
    if ((targetAspect - sourceAspect).abs() < 0.01) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final fullW = constraints.maxWidth;
      final fullH = constraints.maxHeight;
      double cropW = fullW;
      double cropH = fullH;
      if (targetAspect > sourceAspect) {
        // Crop is wider than source frame proportionally -> full width, shorter height.
        cropH = fullW / targetAspect;
      } else {
        cropW = fullH * targetAspect;
      }
      final left = (fullW - cropW) / 2 + offsetX * (fullW - cropW);
      final top = (fullH - cropH) / 2 + offsetY * (fullH - cropH);
      return IgnorePointer(
        child: CustomPaint(
          size: Size(fullW, fullH),
          painter: _CropPainter(Rect.fromLTWH(left, top, cropW, cropH)),
        ),
      );
    });
  }
}

class _CropPainter extends CustomPainter {
  final Rect cropRect;
  const _CropPainter(this.cropRect);

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.6);
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()..addRect(cropRect);
    canvas.drawPath(Path.combine(PathOperation.difference, full, hole), overlay);
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = BinnacleColors.tealBright
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) => oldDelegate.cropRect != cropRect;
}
