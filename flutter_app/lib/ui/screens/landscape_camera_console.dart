// BINNACLE LIVE CAMERA CONSOLE — the landscape presentation of the Live screen.
//
// The video is the primary surface; everything else is a thin, high-contrast
// overlay laid out for one-handed use on a boat (large targets, right-hand
// capture cluster, few words). Non-critical controls fade after a short idle;
// a minimum status HUD never does.
//
// HONESTY. The console is presentation. It receives its behaviour through
// [ConsoleBindings], which the Live screen fills differently for Recorded Demo
// (local digital zoom, local Snapshot/Highlight, simulated Rider Lock) and Core
// Mode (Core commands, Core state). Where Core has no capability yet (Rider
// Lock, RAW view) the control says so instead of pretending.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/clip.dart' as models;
import '../../core/models/vessel_state.dart';
import '../../core/services/camera_media_source.dart';
import '../../core/services/demo_media.dart';
import '../../core/services/track_framing.dart';
import '../../core/services/telemetry_socket.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/telemetry_overlay.dart';
import 'landscape_console_controller.dart';

/// Everything the console can do or show that depends on Demo vs Core.
class ConsoleBindings {
  final bool isDemo;

  // Zoom (Demo: local digital transform; Core: Core-authoritative nudge_zoom).
  final double zoom;
  final double maxZoom;
  final bool pinchEnabled;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final ValueChanged<double> onZoomTo;
  final VoidCallback onZoomToggle;

  // Capture.
  final VoidCallback onSnapshot;
  final VoidCallback onHighlight;
  final ValueChanged<models.Clip> onOpenThumbnail;
  final VoidCallback onExit;

  // View mode.
  final DemoViewMode viewMode;
  final Set<DemoViewMode> enabledViewModes;
  final ValueChanged<DemoViewMode> onViewMode;

  // Rider Lock. In Recorded Demo the rider box is drawn on the video itself
  // (pre-authored spatial annotation) and tapping it locks it. Core has no
  // target data yet, so `framing` is null there and nothing is offered.
  final DemoFraming? framing;
  final String? lockedId;
  final ValueChanged<String> onLock;
  final VoidCallback onClearLock;

  /// MANUAL only: pan the crop by a one-finger drag of this many screen pixels.
  final ValueChanged<Offset> onPanManual;

  const ConsoleBindings({
    required this.isDemo,
    required this.zoom,
    required this.maxZoom,
    required this.pinchEnabled,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomTo,
    required this.onZoomToggle,
    required this.onSnapshot,
    required this.onHighlight,
    required this.onOpenThumbnail,
    required this.onExit,
    required this.viewMode,
    required this.enabledViewModes,
    required this.onViewMode,
    required this.framing,
    required this.lockedId,
    required this.onLock,
    required this.onClearLock,
    required this.onPanManual,
  });
}

class LandscapeCameraConsole extends StatefulWidget {
  final Widget video;
  final CameraMediaSource source;
  final LandscapeConsoleController ui;
  final ConsoleBindings bindings;
  final VesselState vessel;
  final LinkStatus linkStatus;
  final TelemetrySocket telemetry;
  final bool mobActive;
  final Widget mobBanner;
  final String? toast;
  final bool toastIsError;
  final bool flash;
  final bool captureBusy;

  const LandscapeCameraConsole({
    super.key,
    required this.video,
    required this.source,
    required this.ui,
    required this.bindings,
    required this.vessel,
    required this.linkStatus,
    required this.telemetry,
    required this.mobActive,
    required this.mobBanner,
    required this.toast,
    required this.toastIsError,
    required this.flash,
    required this.captureBusy,
  });

  @override
  State<LandscapeCameraConsole> createState() => _LandscapeCameraConsoleState();
}

class _LandscapeCameraConsoleState extends State<LandscapeCameraConsole> {
  double _pinchBase = 1;
  bool _multiTouch = false;
  Offset _dragStart = Offset.zero;
  Offset _dragNow = Offset.zero;

  ConsoleBindings get b => widget.bindings;
  LandscapeConsoleController get ui => widget.ui;

  void _onScaleStart(ScaleStartDetails d) {
    _pinchBase = b.zoom;
    _multiTouch = d.pointerCount >= 2;
    _dragStart = d.focalPoint;
    _dragNow = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    ui.interact();
    _dragNow = d.focalPoint;
    if (d.pointerCount >= 2) {
      _multiTouch = true;
      if (b.pinchEnabled) b.onZoomTo(_pinchBase * d.scale);
    } else if (b.viewMode == DemoViewMode.manual && b.framing != null) {
      // MANUAL: one finger pans the crop (clamped to the video by the framing).
      b.onPanManual(d.focalPointDelta);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Swipe down in the video area = Clean View. Ignored for pinches and for
    // swipes that begin in the top system-gesture strip (status-bar pull-down).
    final delta = _dragNow - _dragStart;
    final topInset = MediaQuery.paddingOf(context).top;
    final startsInSystemStrip = _dragStart.dy < topInset + 28;
    // In MANUAL a one-finger drag pans, so the swipe gesture is not offered
    // there; the Clean View button still works.
    if (!_multiTouch &&
        b.viewMode != DemoViewMode.manual &&
        !startsInSystemStrip &&
        delta.dy > 72 &&
        delta.dy.abs() > delta.dx.abs() * 1.5) {
      ui.enterCleanView();
    }
    _multiTouch = false;
  }

  /// The rider box under [position], if the operator tapped it. Uses the same
  /// FramingGeometry that draws the box, with a generous margin for wet hands.
  bool _hitsRiderBox(Offset position) {
    final framing = b.framing;
    final source = widget.source;
    if (framing == null || source is! DemoRecordedCameraSource) return false;
    final g = framing.geometry;
    final target = framing.target;
    final style = source.boxStyle;
    if (g == null || target == null || style == null) return false;
    // A coasting box is a last-known position, not a confirmed rider.
    if (style == RiderBoxStyle.coasting) return false;
    return g.boxToScreen(target.box).inflate(16).contains(position);
  }

  void _onTapAt(Offset position) {
    if (ui.cleanView) {
      ui.exitCleanView();
      return;
    }
    final target = b.framing?.target;
    if (target != null && _hitsRiderBox(position)) {
      // Tapping the rider on the video locks them: the interaction real Track
      // targets will use.
      ui.interact();
      HapticFeedback.selectionClick();
      b.onLock(target.id);
      return;
    }
    ui.closeRiderPicker();
    ui.interact();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ui,
      builder: (context, _) {
        final visible = ui.controlsVisible;
        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Gesture layer over the video. One scale recognizer handles
              // pinch AND the swipe, so they cannot fight in the arena.
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => ui.interact(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTapAt(d.localPosition),
                  onDoubleTap: () {
                    ui.interact();
                    b.onZoomToggle();
                  },
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: widget.video,
                ),
              ),
              _trackOverlay(),
              SafeArea(
                minimum: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    Align(alignment: Alignment.topLeft, child: _minimumHud()),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 44, bottom: 30),
                        child: _fade(
                          const ValueKey('console-controls-left'),
                          visible,
                          _leftControls(),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 44, bottom: 30),
                        child: _fade(
                          const ValueKey('console-controls-right'),
                          visible,
                          _rightControls(),
                        ),
                      ),
                    ),
                    if (ui.hudExpanded && visible)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 74, top: 20),
                          child: _telemetryPanel(),
                        ),
                      ),
                    if (ui.riderPickerOpen && visible)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 74, top: 20),
                          child: _riderPicker(),
                        ),
                      ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _bottomBar(visible),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 34, left: 150),
                        child: _thumbnail(),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 44),
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: widget.toast == null ? 0 : 1,
                            child: _Toast(
                              text: widget.toast ?? '',
                              isError: widget.toastIsError,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: widget.flash ? 0.85 : 0,
                    child: const ColoredBox(color: Colors.white),
                  ),
                ),
              ),
              Positioned.fill(child: widget.mobBanner),
            ],
          ),
        );
      },
    );
  }

  Widget _fade(Key key, bool visible, Widget child) => IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          key: key,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          opacity: visible ? 1 : 0,
          child: child,
        ),
      );

  // ---- overlays -----------------------------------------------------------

  /// Rider reticle over the video. Presentation only: not scaled with the video
  /// and not a detection box (there is no per-frame detector output here).
  Widget _trackOverlay() {
    return IgnorePointer(
      child: ValueListenableBuilder<VisionTrackState>(
        valueListenable: widget.source.trackState,
        builder: (_, track, __) {
          // Recorded Demo draws its rider box ON the video, from the spatial
          // annotation. This centred reticle is not spatial, so Demo never uses it.
          final showReticle = !b.isDemo &&
              track.riderVisible &&
              b.viewMode == DemoViewMode.trackFollow;
          if (!showReticle) return const SizedBox.shrink();
          return Center(
            child: ProximityReticle(
              riderDistanceM: widget.telemetry.latest.riderDistanceM,
            ),
          );
        },
      ),
    );
  }

  // ---- persistent minimum HUD --------------------------------------------

  String? _warning() {
    final s = widget.vessel;
    if (s.capture.bufferHealth == 'degraded') return 'BUFFER DEGRADED';
    if (!b.isDemo &&
        (widget.linkStatus == LinkStatus.offline ||
            widget.linkStatus == LinkStatus.stale)) {
      return 'CORE LINK LOST';
    }
    if (s.capture.bufferHealth == 'recovering') return 'BUFFER RECOVERING';
    return null;
  }

  Widget _minimumHud() {
    final capture = widget.vessel.capture;
    final warning = _warning();
    final lock = b.isDemo
        ? (b.lockedId == null ? 'TAP RIDER TO LOCK' : 'LOCK · SIM')
        : 'LOCK · N/A';
    final rec = b.isDemo
        ? 'PLAYBACK · NOT REC'
        : capture.recording
            ? 'REC · PASS ${capture.passNumber}'
            : 'BUFFERING';
    final link = switch (widget.linkStatus) {
      LinkStatus.simulated => 'LINK SIMULATED',
      LinkStatus.connecting => 'LINK CONNECTING',
      LinkStatus.connected => 'LINK OK',
      LinkStatus.stale => 'LINK STALE',
      LinkStatus.offline => 'LINK OFFLINE',
    };
    return Padding(
      key: const ValueKey('console-min-hud'),
      padding: const EdgeInsets.only(right: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (widget.source.isRecordedDemo)
            const _Chip(
              text: 'DEMO — RECORDED CAMERA FEED',
              color: BinnacleColors.amber,
              bold: true,
            ),
          ValueListenableBuilder<VisionTrackState>(
            valueListenable: widget.source.trackState,
            builder: (_, t, __) => _Chip(
              text: t.label,
              color: t.riderVisible
                  ? BinnacleColors.tealBright
                  : BinnacleColors.slate,
            ),
          ),
          _Chip(
            text: lock,
            color: b.isDemo && b.lockedId != null
                ? BinnacleColors.tealBright
                : BinnacleColors.slate,
          ),
          _Chip(text: rec, color: BinnacleColors.offWhite),
          // Clean View keeps only the feed, rider/Track indication, recording
          // status, the Demo label and any critical warning.
          if (!ui.cleanView) ...[
            _Chip(text: link, color: BinnacleColors.offWhite),
            _Chip(
              key: const ValueKey('console-zoom-chip'),
              text: '${b.zoom.toStringAsFixed(1)}×',
              color: BinnacleColors.offWhite,
              bold: true,
            ),
          ],
          if (warning != null)
            _Chip(
              key: const ValueKey('console-warning'),
              text: '⚠ $warning',
              color: BinnacleColors.orange,
              bold: true,
            ),
        ],
      ),
    );
  }

  // ---- left column: mode + tools -----------------------------------------

  Widget _leftControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoundBtn(
          key: const ValueKey('console-exit'),
          icon: Icons.arrow_back_rounded,
          tooltip: 'Leave camera console',
          onTap: b.onExit,
        ),
        const SizedBox(height: 8),
        _ViewModeSelector(
          mode: b.viewMode,
          enabled: b.enabledViewModes,
          onChanged: (m) {
            ui.interact();
            b.onViewMode(m);
          },
        ),
        const SizedBox(height: 8),
        _RoundBtn(
          key: const ValueKey('console-rider-lock'),
          icon: b.lockedId != null ? Icons.lock : Icons.person_pin_circle,
          tooltip: b.lockedId != null ? 'Clear Rider Lock' : 'Rider Lock',
          active: ui.riderPickerOpen || b.lockedId != null,
          onTap: () {
            final target = b.framing?.target;
            if (b.framing == null) {
              // Core: no target data exists yet; say so instead of pretending.
              ui.toggleRiderPicker();
            } else if (b.lockedId != null) {
              ui.interact();
              b.onClearLock();
            } else if (target != null &&
                (widget.source is! DemoRecordedCameraSource ||
                    (widget.source as DemoRecordedCameraSource).boxStyle !=
                        RiderBoxStyle.coasting)) {
              ui.interact();
              b.onLock(target.id);
            } else {
              ui.interact();
            }
          },
        ),
        const SizedBox(height: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _RoundBtn(
            key: const ValueKey('console-clean-view'),
            icon: Icons.fullscreen_rounded,
            tooltip: 'Clean View',
            onTap: ui.toggleCleanView,
          ),
          const SizedBox(width: 8),
          _RoundBtn(
            key: const ValueKey('console-hud-toggle'),
            icon: Icons.speed_rounded,
            tooltip: 'Telemetry',
            active: ui.hudExpanded,
            onTap: ui.toggleHud,
          ),
        ]),
      ],
    );
  }

  // ---- right column: zoom + capture --------------------------------------

  Widget _rightControls() {
    const presets = [1.0, 2.0, 3.0, 4.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundBtn(
              key: const ValueKey('console-zoom-in'),
              icon: Icons.add_rounded,
              tooltip: 'Zoom in',
              onTap: b.zoom < b.maxZoom
                  ? () {
                      ui.interact();
                      b.onZoomIn();
                    }
                  : null,
            ),
            const SizedBox(height: 6),
            for (final p in presets)
              if (p <= b.maxZoom + 0.001)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _PresetBtn(
                    key: ValueKey('console-preset-${p.toInt()}'),
                    label: '${p.toInt()}×',
                    selected: (b.zoom - p).abs() < 0.05,
                    onTap: () {
                      ui.interact();
                      b.onZoomTo(p);
                    },
                  ),
                ),
            _RoundBtn(
              key: const ValueKey('console-zoom-out'),
              icon: Icons.remove_rounded,
              tooltip: 'Zoom out',
              onTap: b.zoom > 1.0
                  ? () {
                      ui.interact();
                      b.onZoomOut();
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(width: 14),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _broadcastStatus(),
            const SizedBox(height: 12),
            _RoundBtn(
              key: const ValueKey('console-snapshot'),
              icon: Icons.photo_camera_outlined,
              tooltip: 'Snapshot',
              size: 64,
              iconSize: 28,
              onTap: widget.captureBusy
                  ? null
                  : () {
                      ui.interact();
                      HapticFeedback.lightImpact();
                      b.onSnapshot();
                    },
            ),
            const SizedBox(height: 14),
            _HighlightButton(
              key: const ValueKey('console-highlight'),
              pulse: ui.highlightPulse,
              busy: widget.captureBusy,
              onTap: () {
                ui.interact();
                HapticFeedback.mediumImpact();
                b.onHighlight();
              },
            ),
          ],
        ),
      ],
    );
  }

  /// Status only. Broadcast is not controlled from the console.
  Widget _broadcastStatus() {
    final v = widget.vessel;
    final text = b.isDemo
        ? 'BROADCAST OFF'
        : v.broadcast.live
            ? 'LIVE · ${v.broadcast.viewers}'
            : 'NOT BROADCASTING';
    return _Chip(
      key: const ValueKey('console-broadcast-status'),
      text: text,
      color: !b.isDemo && v.broadcast.live
          ? BinnacleColors.orange
          : BinnacleColors.slate,
    );
  }

  // ---- panels -------------------------------------------------------------

  /// Shown only in Core Mode, where no Track target data exists yet.
  Widget _riderPicker() {
    return _Panel(
      key: const ValueKey('console-rider-note'),
      child: const SizedBox(
        width: 230,
        child: Text(
          'RIDER LOCK\nRider selection needs Binnacle Track target data from '
          'the Core. Not available yet.',
          style: TextStyle(fontSize: 12, color: BinnacleColors.slateLight),
        ),
      ),
    );
  }

  Widget _telemetryPanel() {
    final t = widget.telemetry;
    final has = t.history.isNotEmpty;
    final demo = b.isDemo;
    String simTag(String v) => demo ? '$v (simulated)' : v;
    final rows = <(String, String)>[
      (
        'Boat speed',
        has ? simTag('${t.latest.speedMph.round()} MPH') : 'unavailable'
      ),
      (
        'Rider distance',
        has
            ? simTag('${t.latest.riderDistanceM.toStringAsFixed(0)} m')
            : 'unavailable'
      ),
      ('Camera', demo ? 'recorded file' : widget.linkStatus.name),
      if (demo)
        (
          'Rider box',
          'pre-authored annotation of this footage (not live detection)'
        ),
      ('Wake / rider metrics', 'unavailable'),
      ('Battery / power', 'unavailable'),
    ];
    return _Panel(
      key: const ValueKey('console-telemetry-panel'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${r.$1}  ',
                    style: const TextStyle(
                        fontSize: 12, color: BinnacleColors.slateLight)),
                TextSpan(
                    text: r.$2,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: BinnacleColors.offWhite)),
              ])),
            ),
        ],
      ),
    );
  }

  // ---- bottom -------------------------------------------------------------

  Widget _bottomBar(bool visible) {
    final src = widget.source;
    if (src is DemoRecordedCameraSource) {
      return SizedBox(
        width: double.infinity,
        child: _DemoTimeline(
          key: const ValueKey('console-timeline'),
          source: src,
          showLabels: visible,
          onInteract: ui.interact,
        ),
      );
    }
    // Real Live: no rewinding a live feed. Show only what actually exists.
    final c = widget.vessel.capture;
    return IgnorePointer(
      child: AnimatedOpacity(
        key: const ValueKey('console-live-buffer'),
        duration: const Duration(milliseconds: 250),
        opacity: visible ? 1 : 0,
        child: _Chip(
          text: 'ROLLING BUFFER ${c.bufferHealth.toUpperCase()} · '
              'HIGHLIGHT −${c.preRollSeconds}s/+${c.postRollSeconds}s',
          color: BinnacleColors.offWhite,
        ),
      ),
    );
  }

  Widget _thumbnail() {
    final clip = ui.thumbnail;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: clip == null
          ? const SizedBox.shrink(key: ValueKey('no-thumb'))
          : GestureDetector(
              key: const ValueKey('console-snapshot-thumbnail'),
              onTap: () {
                ui.dismissThumbnail();
                b.onOpenThumbnail(clip);
              },
              child: Container(
                width: 112,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BinnacleColors.offWhite, width: 2),
                  color: BinnacleColors.navyDeep,
                ),
                clipBehavior: Clip.antiAlias,
                child: clip.localPath == null
                    ? const Icon(Icons.image_outlined)
                    : Image.file(
                        File(clip.localPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image_not_supported_outlined),
                      ),
              ),
            ),
    );
  }
}

// ---- small building blocks ---------------------------------------------------

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final bool bold;
  const _Chip(
      {super.key, required this.text, required this.color, this.bold = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: BinnacleColors.navyDeep.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Text(
          text,
          style: BinnacleTheme.mono(
              size: 11.5,
              color: color,
              weight: bold ? FontWeight.w800 : FontWeight.w600),
        ),
      );
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BinnacleColors.navyDeep.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: BinnacleColors.offWhite.withValues(alpha: 0.18)),
        ),
        child: child,
      );
}

class _Toast extends StatelessWidget {
  final String text;
  final bool isError;
  const _Toast({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: (isError ? BinnacleColors.orange : BinnacleColors.teal)
              .withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: isError ? Colors.white : BinnacleColors.navyDeep,
          ),
        ),
      );
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final double size;
  final double iconSize;
  const _RoundBtn({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.size = 48,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: tooltip,
      enabled: enabled,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BinnacleColors.navyDeep.withValues(alpha: 0.78),
            border: Border.all(
              color: active
                  ? BinnacleColors.tealBright
                  : BinnacleColors.offWhite
                      .withValues(alpha: enabled ? 0.55 : 0.15),
              width: active ? 2.5 : 1.5,
            ),
          ),
          child: Icon(icon,
              size: iconSize,
              color: !enabled
                  ? BinnacleColors.slateDim
                  : active
                      ? BinnacleColors.tealBright
                      : BinnacleColors.offWhite),
        ),
      ),
    );
  }
}

class _PresetBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PresetBtn(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected
                ? BinnacleColors.teal
                : BinnacleColors.navyDeep.withValues(alpha: 0.78),
            border: Border.all(
                color: BinnacleColors.offWhite
                    .withValues(alpha: selected ? 0.9 : 0.4)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? BinnacleColors.navyDeep
                      : BinnacleColors.offWhite)),
        ),
      );
}

class _ViewModeSelector extends StatelessWidget {
  final DemoViewMode mode;
  final Set<DemoViewMode> enabled;
  final ValueChanged<DemoViewMode> onChanged;
  const _ViewModeSelector(
      {required this.mode, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = {
      DemoViewMode.raw: 'RAW',
      DemoViewMode.trackFollow: 'TRACK FOLLOW',
      DemoViewMode.manual: 'MANUAL',
    };
    return Container(
      key: const ValueKey('console-view-modes'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: BinnacleColors.navyDeep.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: BinnacleColors.offWhite.withValues(alpha: 0.3)),
      ),
      // IntrinsicWidth keeps the stretched rows as wide as the longest label.
      // Without it the column would fill the whole display width and swallow
      // every touch meant for the video.
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in DemoViewMode.values)
              GestureDetector(
                key: ValueKey('console-mode-${m.name}'),
                onTap: enabled.contains(m) ? () => onChanged(m) : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: m == mode ? BinnacleColors.teal : Colors.transparent,
                  ),
                  child: Text(
                    labels[m]!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: !enabled.contains(m)
                          ? BinnacleColors.slateDim
                          : m == mode
                              ? BinnacleColors.navyDeep
                              : BinnacleColors.offWhite,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The shutter-sized Save Highlight control with a ring pulse on each save.
class _HighlightButton extends StatelessWidget {
  final int pulse;
  final bool busy;
  final VoidCallback onTap;
  const _HighlightButton(
      {super.key,
      required this.pulse,
      required this.busy,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    const size = 96.0;
    return SizedBox(
      width: size + 28,
      height: size + 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (pulse > 0)
            IgnorePointer(
              child: TweenAnimationBuilder<double>(
                key: ValueKey('ring-$pulse'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOut,
                builder: (_, t, __) => Opacity(
                  opacity: (1 - t).clamp(0, 1),
                  child: Container(
                    width: size + 28 * t,
                    height: size + 28 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: BinnacleColors.tealBright, width: 4),
                    ),
                  ),
                ),
              ),
            ),
          Semantics(
            button: true,
            label: 'Save Highlight',
            child: GestureDetector(
              onTap: busy ? null : onTap,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: busy ? BinnacleColors.slateDim : BinnacleColors.teal,
                  border: Border.all(color: BinnacleColors.offWhite, width: 4),
                ),
                child: const Text(
                  'SAVE\nHIGHLIGHT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1.15,
                    color: BinnacleColors.navyDeep,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin recorded-source timeline. Dragging seeks the video player, which stays
/// the only clock: the position shown here is the position the player reports.
class _DemoTimeline extends StatefulWidget {
  final DemoMediaControls source;
  final bool showLabels;
  final VoidCallback onInteract;
  const _DemoTimeline(
      {super.key,
      required this.source,
      required this.showLabels,
      required this.onInteract});

  @override
  State<_DemoTimeline> createState() => _DemoTimelineState();
}

class _DemoTimelineState extends State<_DemoTimeline> {
  double? _scrub; // 0..1 while dragging

  Future<void> _seekFraction(double f) async {
    final total = widget.source.sourceDuration;
    if (total == null) return;
    final target = Duration(
        milliseconds: (total.inMilliseconds * f.clamp(0.0, 1.0)).round());
    try {
      await widget.source.seekTo(target);
    } catch (_) {
      // Player not ready: leave the position where the player says it is.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.source.position,
      builder: (_, pos, __) {
        final total = widget.source.sourceDuration;
        final ms = total?.inMilliseconds ?? 0;
        final playFrac =
            ms == 0 ? 0.0 : (pos.inMilliseconds / ms).clamp(0.0, 1.0);
        final frac = _scrub ?? playFrac;
        final shown = _scrub != null && total != null
            ? Duration(milliseconds: (ms * _scrub!).round())
            : pos;
        return LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : 400.0;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              widget.onInteract();
              _seekFraction(d.localPosition.dx / w);
            },
            onHorizontalDragStart: (_) => widget.onInteract(),
            onHorizontalDragUpdate: (d) {
              widget.onInteract();
              setState(() => _scrub = (d.localPosition.dx / w).clamp(0.0, 1.0));
            },
            onHorizontalDragEnd: (_) async {
              final f = _scrub;
              if (f != null) await _seekFraction(f);
              if (mounted) setState(() => _scrub = null);
            },
            child: SizedBox(
              height: 30,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: widget.showLabels ? 1 : 0,
                    child: Text(
                      '${formatDemoTime(shown)} / ${formatDemoTime(total ?? Duration.zero)}  ·  RECORDED SOURCE',
                      style: BinnacleTheme.mono(
                          size: 10.5, color: BinnacleColors.offWhite),
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 4,
                    child: Stack(children: [
                      Container(color: Colors.white24),
                      FractionallySizedBox(
                        widthFactor: frac,
                        child: Container(color: BinnacleColors.tealBright),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }
}
