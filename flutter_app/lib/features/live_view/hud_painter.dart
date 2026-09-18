// Sunlight-readable tracking HUD, painted as a CustomPainter stacked on
// top of the live video surface (see live_view_screen.dart). High
// contrast + heavy stroke widths + a dark outline behind every stroke are
// deliberate: this has to stay legible on a phone screen outdoors, not
// just look good on an indoor dev monitor.

import 'package:flutter/material.dart';

import 'telemetry_frame.dart';

/// Colors are chosen for state legibility first, brand palette second —
/// a HUD that goes green/amber/red like a status light reads faster at a
/// glance (including for colorblind-adjacent hue confusion, since these
/// three are also separated by brightness) than three shades of teal
/// would.
Color colorForState(TrackingState state) {
  switch (state) {
    case TrackingState.tracking:
      return const Color(0xFF3DDC84); // locked-on, confident
    case TrackingState.coasting:
      return const Color(0xFFFFC531); // predicted, not re-detected yet
    case TrackingState.fallCandidate:
      return const Color(0xFFFF3B30); // needs attention now
    case TrackingState.lost:
    case TrackingState.unknown:
      return const Color(0xFF9CACB9); // neutral — nothing confident to show
  }
}

String labelForState(TrackingState state) {
  switch (state) {
    case TrackingState.tracking:
      return 'TRACKING';
    case TrackingState.coasting:
      return 'COASTING';
    case TrackingState.fallCandidate:
      return 'FALL CANDIDATE';
    case TrackingState.lost:
      return 'LOST';
    case TrackingState.unknown:
      return 'UNKNOWN';
  }
}

/// Maps a video-space [NormalizedBBox] (fractions of the *source frame*,
/// always full-frame regardless of how it's displayed) onto the actual
/// on-screen rect the video occupies inside [canvasSize], given the
/// video's own aspect ratio. Handles both letterboxing (video narrower
/// than the canvas) and pillarboxing (video taller than the canvas) for
/// a `BoxFit.contain`-style video surface, which is what RTCVideoView
/// uses by default — a naive `bbox * canvasSize` scale is only correct
/// when the video exactly fills the canvas, which is not guaranteed for
/// arbitrary screen aspect ratios.
Rect mapNormalizedBoxToCanvas({
  required NormalizedBBox bbox,
  required Size canvasSize,
  required double videoAspectRatio,
}) {
  final canvasAspect = canvasSize.width / canvasSize.height;
  double contentWidth;
  double contentHeight;
  double offsetX = 0;
  double offsetY = 0;

  if (videoAspectRatio > canvasAspect) {
    // Video is relatively wider than the canvas -> letterboxed top/bottom.
    contentWidth = canvasSize.width;
    contentHeight = contentWidth / videoAspectRatio;
    offsetY = (canvasSize.height - contentHeight) / 2;
  } else {
    // Video is relatively taller than the canvas -> pillarboxed left/right.
    contentHeight = canvasSize.height;
    contentWidth = contentHeight * videoAspectRatio;
    offsetX = (canvasSize.width - contentWidth) / 2;
  }

  return Rect.fromLTWH(
    offsetX + bbox.x * contentWidth,
    offsetY + bbox.y * contentHeight,
    bbox.w * contentWidth,
    bbox.h * contentHeight,
  );
}

class HudPainter extends CustomPainter {
  final TelemetryFrame? frame;

  /// Source video width/height (e.g. from the renderer's reported track
  /// size). Defaults to 16:9 when unknown so boxes still render sanely
  /// before the first video frame reports its real dimensions.
  final double videoAspectRatio;

  HudPainter({required this.frame, this.videoAspectRatio = 16 / 9});

  static const _bracketLength = 22.0;
  static const _strokeWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = this.frame;
    if (frame == null || frame.riders.isEmpty) return;

    final color = colorForState(frame.state);
    for (final rider in frame.riders) {
      final rect = mapNormalizedBoxToCanvas(
        bbox: rider.bbox,
        canvasSize: size,
        videoAspectRatio: videoAspectRatio,
      );
      _drawCornerBrackets(canvas, rect, color);
      _drawTag(canvas, rect, rider, frame.state, color);
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Color color) {
    final len = _bracketLength.clamp(0.0, rect.shortestSide / 2);

    // Dark outline drawn first, underneath the bright stroke, so the
    // bracket reads against both dark water and bright sky/foam.
    final outline = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth + 2
      ..strokeCap = StrokeCap.round;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;

    final corners = <List<Offset>>[
      // top-left
      [rect.topLeft, rect.topLeft + Offset(len, 0)],
      [rect.topLeft, rect.topLeft + Offset(0, len)],
      // top-right
      [rect.topRight, rect.topRight + Offset(-len, 0)],
      [rect.topRight, rect.topRight + Offset(0, len)],
      // bottom-left
      [rect.bottomLeft, rect.bottomLeft + Offset(len, 0)],
      [rect.bottomLeft, rect.bottomLeft + Offset(0, -len)],
      // bottom-right
      [rect.bottomRight, rect.bottomRight + Offset(-len, 0)],
      [rect.bottomRight, rect.bottomRight + Offset(0, -len)],
    ];

    for (final paint in [outline, stroke]) {
      for (final segment in corners) {
        canvas.drawLine(segment[0], segment[1], paint);
      }
    }
  }

  void _drawTag(
    Canvas canvas,
    Rect rect,
    RiderTrack rider,
    TrackingState state,
    Color color,
  ) {
    final confidencePct = (rider.confidence * 100).round();
    final text =
        '${labelForState(state)}  #${rider.trackId}  $confidencePct%';

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 8.0;
    const paddingV = 4.0;
    final tagWidth = painter.width + paddingH * 2;
    final tagHeight = painter.height + paddingV * 2;

    // Anchor above the box; if there isn't room above (box near the top
    // edge), drop it just inside the top of the box instead of letting it
    // clip off-canvas.
    final tagTop = rect.top - tagHeight - 4 >= 0
        ? rect.top - tagHeight - 4
        : rect.top + 4;
    final tagRect =
        Rect.fromLTWH(rect.left, tagTop, tagWidth, tagHeight);

    final bgPaint = Paint()..color = color.withValues(alpha: 0.92);
    final rrect = RRect.fromRectAndRadius(tagRect, const Radius.circular(4));
    canvas.drawRRect(rrect, bgPaint);

    // Text is always solid black/white against the flat state color
    // rather than colored-on-colored, which is what keeps it legible in
    // direct sunlight regardless of which state color is active.
    final textColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
    painter.text = TextSpan(text: text, style: painter.text!.style!.copyWith(color: textColor));
    painter.layout();
    painter.paint(canvas, tagRect.topLeft + const Offset(paddingH, paddingV));
  }

  @override
  bool shouldRepaint(covariant HudPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.videoAspectRatio != videoAspectRatio;
  }
}

/// Convenience widget wrapping [HudPainter] so screens don't construct
/// CustomPaint boilerplate directly.
class HudOverlay extends StatelessWidget {
  final TelemetryFrame? frame;
  final double videoAspectRatio;

  const HudOverlay({
    super.key,
    required this.frame,
    this.videoAspectRatio = 16 / 9,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: HudPainter(frame: frame, videoAspectRatio: videoAspectRatio),
        size: Size.infinite,
      ),
    );
  }
}
