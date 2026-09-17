import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/models/clip.dart' show ClipKind;
import '../../core/models/vessel_state.dart';
import '../../core/services/control_channel_service.dart';
import '../../core/services/command_result.dart';
import '../../core/services/mob_alert_state.dart';
import '../../core/services/pairing_service.dart';
import '../../core/services/telemetry_socket.dart';
import '../../core/services/webrtc_service.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/eptz_video_view.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/mob_alert_banner.dart';
import '../widgets/simulated_wake_view.dart';
import '../widgets/telemetry_overlay.dart';
import 'library_screen.dart' show ClipRepository;

// Layout and componentry follow the retro-hero / technical-instrument UX
// prototype's capture screen (screen-capture) as closely as native widgets
// allow: topbar + health readout, preset pills, a full-width link bar, the
// rec-state pill, a 16:9 viewport with HUD tags / zoom column / capture row,
// the go-live bar, and the quick-adjust handle. See spotter-v5 prototype.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final WebRtcService _webrtc;
  bool _flash = false;
  String? _saveToast;
  bool _saveToastIsError = false;
  Timer? _toastTimer;
  String _preset = 'wakesurf';

  @override
  void initState() {
    super.initState();
    _webrtc = WebRtcService(
      renderer: AppConfig.isDemo
          ? SimulatedVideoRenderer()
          : RtcVideoRenderer(control: context.read<ControlChannelService>()),
    );
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _webrtc.dispose();
    super.dispose();
  }

  void _fireFlash() {
    setState(() => _flash = true);
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  void _showSaveToast(String text, {bool isError = false}) {
    _toastTimer?.cancel();
    setState(() {
      _saveToast = text;
      _saveToastIsError = isError;
    });
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saveToast = null);
    });
  }

  /// A spectator's allowed command set is empty by design (§3) — every
  /// command throws CommandRejected until this device is paired as crew or
  /// owner. This is used for fire-and-forget UI actions (zoom, presets,
  /// trigger mode, arm/disarm) where there is nothing further to confirm;
  /// actions with a real outcome to wait on (capture, MOB acknowledge) go
  /// through sendConfirmed directly instead — see [_capture]/
  /// [_acknowledgeMob] — rather than swallowing the outcome here.
  static bool _send(void Function() action) {
    try {
      action();
      return true;
    } on CommandRejected {
      return false;
    }
  }

  Future<void> _capture(ControlChannelService control, ClipKind kind) async {
    if (AppConfig.isDemo) {
      context.read<ClipRepository>().addFromCapture(kind: kind, preset: _preset);
      if (kind == ClipKind.photo) _fireFlash();
      _showSaveToast('Demo capture saved');
      return;
    }
    final command = kind == ClipKind.photo ? 'snapshot' : 'save_highlight';
    if (control.isPending(command)) return;
    try {
      _showSaveToast('Waiting for Core confirmation');
      final result = await control.sendConfirmed(command, kind == ClipKind.photo ? {} : {
        'pre_s': control.state.capture.preRollSeconds,
        'post_s': control.state.capture.postRollSeconds,
      });
      if (!mounted) return;
      if (result.outcome == CommandOutcome.acknowledged) {
        _showSaveToast('Core acknowledged — media availability pending');
      } else {
        _showSaveToast('Capture not confirmed: ${result.outcome.name}', isError: true);
      }
    } on CommandRejected {
      if (mounted) _showSaveToast('Capture unavailable — check pairing and Core link', isError: true);
    }
  }

  /// BIN-9: the banner must not clear on a button press. Demo mode has no
  /// Core to confirm against, so its local "Acknowledge" tap clears
  /// immediately by design and fabricates a demo fall clip, matching the
  /// existing demo capture flow. Core mode clears ONLY after
  /// ControlChannelService.acknowledgeMob() actually resolves to
  /// [CommandOutcome.acknowledged] — and does not fabricate a clip locally,
  /// since a real "fall" highlight only ever exists once the Core media
  /// catalog reports it (see ClipRepository.addFromCapture, which throws
  /// outside demo mode for exactly this reason). If Core's own next state
  /// update still reports the event active, MobAlertState.applyCoreEvent
  /// re-asserts it — Core remains the final authority regardless of what
  /// this button does locally.
  Future<void> _acknowledgeMob(ControlChannelService control, MobAlertState mobAlert) async {
    if (AppConfig.isDemo) {
      context.read<ClipRepository>().addFromCapture(kind: ClipKind.fall, preset: _preset);
      mobAlert.acknowledgeLocally();
      return;
    }
    if (control.isPending('acknowledge_mob')) return;
    try {
      final result = await control.acknowledgeMob(actor: 'levi');
      if (!mounted) return;
      if (result.outcome == CommandOutcome.acknowledged) {
        mobAlert.acknowledgeLocally();
      } else {
        _showSaveToast('Acknowledge not confirmed: ${result.outcome.name}', isError: true);
      }
    } on CommandRejected {
      if (mounted) _showSaveToast('Acknowledge unavailable — check pairing and Core link', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final control = context.watch<ControlChannelService>();
    final telemetry = context.watch<TelemetrySocket>();
    final mobAlert = context.watch<MobAlertState>();
    final pairing = context.watch<PairingService>();
    final state = control.state;

    // Same idempotent trigger pattern as main.dart's control.connect() call
    // — guarded by status so it fires exactly once per real transition, not
    // once per rebuild. Video only makes sense once the Core link itself is
    // up; there's no point offering a video stream over a dead control
    // channel.
    if (!AppConfig.isDemo && control.hasCurrentState && _webrtc.status == WebRtcLinkStatus.idle) {
      _webrtc.connectToVessel(pairing.credential!.deviceId);
    } else if (!AppConfig.isDemo &&
        !control.hasCurrentState &&
        _webrtc.status != WebRtcLinkStatus.idle) {
      _webrtc.disconnect();
    }

    return Scaffold(
      backgroundColor: BinnacleColors.navyDeep,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (control.hasCurrentState) _TopBar(health: state.health, ts: state.ts)
            else const ListTile(title: Text('Connect'), subtitle: Text('Core health unavailable')),
            _PresetRow(
              selected: _preset,
              onPreset: (p) {
                setState(() => _preset = p);
                _send(() => control.loadPreset(p, actor: 'levi'));
              },
            ),
            const SizedBox(height: 2),
            _LinkBar(
              status: control.status,
              lastSeen: control.lastSeen,
              seq: state.seq,
              everConnected: control.everConnected,
              lastKnownRecording: control.lastKnownRecording,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: state.framing.isManual
                    ? Column(
                        key: const ValueKey('manual-flag'),
                        children: [
                          const SizedBox(height: 9),
                          _ManualFramingFlag(
                              onHandBack: () => _send(() => control.setControlMode('ai', actor: 'levi'))),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('no-flag')),
              ),
            ),
            const SizedBox(height: 9),
            if (control.hasCurrentState) _RecStateCard(capture: state.capture)
            else const Text('Recording state unknown — awaiting Core'),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    EptzVideoView(
                      service: _webrtc,
                      simulatedBuilder: (_) => Stack(
                        fit: StackFit.expand,
                        children: [
                          const SimulatedWakeView(),
                          Center(
                            child: ProximityReticle(riderDistanceM: telemetry.latest.riderDistanceM),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 9,
                      left: 9,
                      child: _HudTag(text: '${state.triggerMode.toUpperCase()} TRIGGER'),
                    ),
                    // Physical-device finding (BIN-36, S25 Ultra): this tag and
                    // EptzVideoView's demo-only SIMULATED badge both anchor to
                    // the video viewport's top-right corner, so in demo mode
                    // they rendered on top of each other, illegibly — on a
                    // device this app's own design explicitly says the
                    // SIMULATED label must never be ambiguous. Offsetting this
                    // tag below the badge only when demo mode actually shows
                    // one, rather than moving the badge itself, keeps
                    // EptzVideoView's own layout untouched.
                    Positioned(
                      top: AppConfig.isDemo ? 44 : 9,
                      right: 9,
                      child: const _HudTag(text: '16:9 · 1080p', dim: true),
                    ),
                    Positioned(left: 9, bottom: 54, child: TelemetryOverlay(telemetry: telemetry)),
                    Positioned(
                      right: 9,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ZoomColumn(
                          zoom: state.framing.zoom,
                          maxZoom: state.framing.maxZoom,
                          onZoomIn: () => _send(() => control.nudgeZoom(0.5, actor: 'levi')),
                          onZoomOut: () => _send(() => control.nudgeZoom(-0.5, actor: 'levi')),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 9,
                      child: _CaptureRow(
                        manual: state.framing.isManual,
                        onSnapshot: () => _capture(control, ClipKind.photo),
                        onHighlight: () => _capture(control, ClipKind.highlight),
                        onOrient: () => _send(() => control.setControlMode(
                              state.framing.isManual ? 'ai' : 'manual',
                              actor: 'levi',
                            )),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: _flash ? 0.85 : 0,
                          child: Container(color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 72,
                      child: IgnorePointer(
                        child: Center(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _saveToast == null ? 0 : 1,
                            child: _SaveToast(text: _saveToast ?? '', isError: _saveToastIsError),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: MobAlertBanner(
                        active: mobAlert.active,
                        lat: mobAlert.lat,
                        lon: mobAlert.lon,
                        headingDegrees: mobAlert.headingDegrees,
                        simulated: mobAlert.simulated,
                        onAcknowledge: () => _acknowledgeMob(control, mobAlert),
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            if (control.canBroadcast('boat')) _GoLiveBar(control: control, broadcast: state.broadcast),
            const SizedBox(height: 11),
            _QuickAdjustHandle(
              control: control,
              triggerMode: state.triggerMode,
              capture: state.capture,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  _ArmSwitchRow(control: control, capture: state.capture),
                  const SizedBox(height: 12),
                  _SafetyCard(safety: state.safety),
                  // Demo-only: a Core-mode build must never let a local tap
                  // fabricate a man-overboard alert — MobAlertState in Core
                  // mode only ever reflects what Core reported (see
                  // mob_alert_state.dart), and triggerDemo() itself throws
                  // outside demo mode as a second layer of defense.
                  if (AppConfig.isDemo) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            mobAlert.active ? mobAlert.acknowledgeLocally() : mobAlert.triggerDemo(),
                        icon: const Icon(Icons.warning_amber_rounded),
                        label: const Text('Simulate fall alert (demo)'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final HealthState health;
  final DateTime ts;
  const _TopBar({required this.health, required this.ts});

  static String _stateAge(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    return s < 60 ? '${s}s' : '${s ~/ 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Connect', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
          Row(
            children: [
              // No network transport diagnostics exist in the wire schema
              // yet (this read a hardcoded '⇅ LAN' before — a fabricated
              // value the Core never reported). State-message age is real,
              // Core-reported data instead.
              Text(
                '◉ ${health.tempC.toStringAsFixed(0)}°C   ▮ ${health.storageFreePct}%   ⟳ ${_stateAge(ts)}',
                style: BinnacleTheme.mono(size: 10),
              ),
              const SizedBox(width: 10),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: BinnacleColors.navyRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: BinnacleColors.offWhite.withValues(alpha: 0.09)),
                ),
                child: const Icon(Icons.person_outline, size: 17, color: BinnacleColors.slate),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  final String selected;
  final void Function(String) onPreset;
  const _PresetRow({required this.selected, required this.onPreset});

  static const presets = [
    ('wakesurf', 'Wakesurf'),
    ('wakeboard', 'Wakeboard'),
    ('ski', 'Ski'),
    ('tube', 'Tube'),
    ('swim', 'Swim'),
    ('cruise', 'Cruising'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          final (id, label) = presets[i];
          final on = id == selected;
          return GestureDetector(
            onTap: () => onPreset(id),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: on ? BinnacleColors.teal.withValues(alpha: 0.1) : BinnacleColors.navy,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: on ? BinnacleColors.teal : BinnacleColors.offWhite.withValues(alpha: 0.09)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: on ? BinnacleColors.tealBright : BinnacleColors.slate,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LinkBar extends StatelessWidget {
  final LinkStatus status;
  final DateTime lastSeen;
  final int seq;

  /// Whether this ControlChannelService has EVER received a real state
  /// message this session (BIN-9) — distinguishes "never connected" from
  /// "was connected, now offline," which the status enum alone cannot.
  final bool everConnected;

  /// The last Core-reported recording flag, or null if Core has never told
  /// us either way. Never assume recording from a stale connection alone.
  final bool? lastKnownRecording;

  const _LinkBar({
    required this.status,
    required this.lastSeen,
    required this.seq,
    required this.everConnected,
    required this.lastKnownRecording,
  });

  /// The subtitle for stale/offline: what we actually know about recording
  /// as of the last real contact, never a claim about the current instant.
  /// Per §1.1/§4.3 the Core keeps recording regardless of this link — but
  /// that autonomy claim is only honest to make once a state message
  /// actually confirmed recording was happening; absent that, the honest
  /// answer is "we never confirmed," not "still recording."
  String _lastKnownLine() => switch (lastKnownRecording) {
        true => 'Vision was recording as of ${_ago(lastSeen)} — Core continues autonomously without this link',
        false => 'Not recording as of ${_ago(lastSeen)}',
        null => 'Recording was never confirmed before the link dropped',
      };

  @override
  Widget build(BuildContext context) {
    final (title, sub, dot, border, bg) = switch (status) {
      LinkStatus.simulated => (
          'Simulated',
          'No Vision device paired',
          BinnacleColors.slateDim,
          BinnacleColors.offWhite.withValues(alpha: 0.09),
          BinnacleColors.navy,
        ),
      LinkStatus.connecting => (
          'Connecting…',
          'Reaching Vision',
          BinnacleColors.amber,
          BinnacleColors.offWhite.withValues(alpha: 0.09),
          BinnacleColors.navy,
        ),
      LinkStatus.connected => (
          'Connected',
          'Vision is online',
          BinnacleColors.tealBright,
          BinnacleColors.teal.withValues(alpha: 0.45),
          BinnacleColors.navy,
        ),
      // Stale = still officially "connected" but silent past the freshness
      // window — a last-known state, not a fresh one, and not yet a
      // disconnect either.
      LinkStatus.stale => (
          'Not responding',
          _lastKnownLine(),
          BinnacleColors.amber,
          BinnacleColors.amber,
          BinnacleColors.amber.withValues(alpha: 0.07),
        ),
      LinkStatus.offline when !everConnected => (
          'Never connected',
          'No state received yet this session',
          BinnacleColors.orange,
          BinnacleColors.orange,
          BinnacleColors.orange.withValues(alpha: 0.08),
        ),
      LinkStatus.offline => (
          'Offline',
          _lastKnownLine(),
          BinnacleColors.orange,
          BinnacleColors.orange,
          BinnacleColors.orange.withValues(alpha: 0.08),
        ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          _PulsingDot(color: dot, pulsing: status == LinkStatus.stale || status == LinkStatus.offline),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                Text(sub, style: TextStyle(fontSize: 10.5, color: BinnacleColors.slate)),
              ],
            ),
          ),
          Text('seq $seq', style: BinnacleTheme.mono(size: 9.5, color: BinnacleColors.slateDim)),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    return s < 60 ? '${s}s ago' : '${s ~/ 60}m ago';
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _PulsingDot({required this.color, this.pulsing = false});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulsing) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Opacity(
        opacity: widget.pulsing ? 1 - (_c.value * 0.7) : 1,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _ManualFramingFlag extends StatelessWidget {
  final VoidCallback onHandBack;
  const _ManualFramingFlag({required this.onHandBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: BinnacleColors.amber.withValues(alpha: 0.1),
        border: Border.all(color: BinnacleColors.amber),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(children: [
        const Icon(Icons.pan_tool_alt_outlined, color: BinnacleColors.amber, size: 15),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('MANUAL FRAMING — AI is not controlling the shot',
              style: TextStyle(color: BinnacleColors.amber, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
        GestureDetector(
          onTap: onHandBack,
          child: Text('Hand back to AI',
              style: BinnacleTheme.mono(size: 10.5, color: BinnacleColors.amber, weight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _RecStateCard extends StatelessWidget {
  final CaptureState capture;
  const _RecStateCard({required this.capture});

  @override
  Widget build(BuildContext context) {
    final recording = capture.recording;
    final (bufLabel, bufFill, bufColor) = switch (capture.bufferHealth) {
      'recovering' => ('BUFFER RECOVERING', 0.5, BinnacleColors.amber),
      'degraded' => ('BUFFER DEGRADED', 0.2, BinnacleColors.orange),
      _ => ('BUFFER OK', 1.0, BinnacleColors.tealBright),
    };
    final borderColor = recording ? BinnacleColors.orange : BinnacleColors.offWhite.withValues(alpha: 0.09);
    final bgColor = recording ? BinnacleColors.orange.withValues(alpha: 0.08) : BinnacleColors.navy;
    final dotColor = recording ? BinnacleColors.orange : BinnacleColors.tealBright;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _PulsingDot(color: dotColor, pulsing: recording),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recording ? 'Recording — pass ${capture.passNumber}' : 'Buffering',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13.5),
                ),
                Text(
                  recording ? 'trigger: ${capture.triggerSource}' : 'Ready — nothing missed',
                  style: BinnacleTheme.mono(size: 10.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(bufLabel, style: BinnacleTheme.mono(size: 9.5, color: BinnacleColors.tealBright)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  width: 48,
                  height: 3,
                  child: LinearProgressIndicator(
                    value: bufFill,
                    backgroundColor: BinnacleColors.offWhite.withValues(alpha: 0.09),
                    valueColor: AlwaysStoppedAnimation(bufColor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HudTag extends StatelessWidget {
  final String text;
  final bool dim;
  const _HudTag({required this.text, this.dim = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BinnacleColors.navyDeep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(text, style: BinnacleTheme.mono(size: 9.5, color: dim ? BinnacleColors.slate : BinnacleColors.offWhite)),
    );
  }
}

class _ZoomColumn extends StatelessWidget {
  final double zoom;
  final double maxZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  const _ZoomColumn({required this.zoom, required this.maxZoom, required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    Widget circleBtn(String label, VoidCallback? onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BinnacleColors.navyDeep.withValues(alpha: 0.62),
              shape: BoxShape.circle,
              border: Border.all(color: BinnacleColors.offWhite.withValues(alpha: onTap == null ? 0.08 : 0.25)),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: onTap == null ? BinnacleColors.slateDim : BinnacleColors.offWhite,
                )),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          circleBtn('+', zoom < maxZoom ? onZoomIn : null),
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: BinnacleColors.navyDeep.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text('${zoom.toStringAsFixed(1)}×', style: BinnacleTheme.mono(size: 10, color: BinnacleColors.offWhite)),
          ),
          const SizedBox(height: 7),
          circleBtn('−', zoom > 1.0 ? onZoomOut : null),
        ],
      ),
    );
  }
}

class _CaptureRow extends StatelessWidget {
  final bool manual;
  final VoidCallback onSnapshot;
  final VoidCallback onHighlight;
  final VoidCallback onOrient;
  const _CaptureRow({
    required this.manual,
    required this.onSnapshot,
    required this.onHighlight,
    required this.onOrient,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CapSideButton(icon: Icons.camera_alt_outlined, onTap: onSnapshot),
        const SizedBox(width: 20),
        _PressScale(
          onTap: onHighlight,
          child: Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BinnacleColors.teal,
              shape: BoxShape.circle,
              border: Border.all(color: BinnacleColors.offWhite.withValues(alpha: 0.85), width: 3),
            ),
            child: const Text(
              'SAVE\nHIGHLIGHT',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w700,
                fontSize: 10,
                height: 1.15,
                color: BinnacleColors.navyDeep,
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        _CapSideButton(icon: Icons.crop_rotate_outlined, onTap: onOrient, active: manual),
      ],
    );
  }
}

class _CapSideButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _CapSideButton({required this.icon, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BinnacleColors.navyDeep.withValues(alpha: 0.62),
          shape: BoxShape.circle,
          border: Border.all(color: active ? BinnacleColors.tealBright : BinnacleColors.offWhite.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, size: 18, color: active ? BinnacleColors.tealBright : BinnacleColors.offWhite),
      ),
    );
  }
}

/// Tactile press feedback (spring back on release) for the capture-row
/// buttons — a plain GestureDetector's tap has no visual acknowledgment
/// until whatever it triggers finishes, which reads as unresponsive on a
/// touch device.
class _PressScale extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _PressScale({required this.onTap, required this.child});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _SaveToast extends StatelessWidget {
  final String text;
  final bool isError;
  const _SaveToast({required this.text, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isError ? BinnacleColors.orange : BinnacleColors.teal).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Space Grotesk',
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: isError ? Colors.white : BinnacleColors.navyDeep,
        ),
      ),
    );
  }
}

class _GoLiveBar extends StatelessWidget {
  final ControlChannelService control;
  final BroadcastState broadcast;
  const _GoLiveBar({required this.control, required this.broadcast});

  @override
  Widget build(BuildContext context) {
    final live = broadcast.live;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: live ? BinnacleColors.orange.withValues(alpha: 0.08) : BinnacleColors.navy,
        border: Border.all(color: live ? BinnacleColors.orange : BinnacleColors.offWhite.withValues(alpha: 0.09)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _PulsingDot(color: live ? BinnacleColors.orange : BinnacleColors.slateDim, pulsing: live),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(live ? 'Live · ${broadcast.viewers} watching' : 'Go live',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  live ? 'Link quality: ${broadcast.linkQuality}' : 'Share this view — on the boat or to the world',
                  style: TextStyle(fontSize: 10.5, color: BinnacleColors.slate),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _CaptureScreenState._send(() => live
                ? control.stopBroadcast(actor: 'levi')
                : control.startBroadcast('boat', actor: 'levi')),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: live ? BinnacleColors.orange : BinnacleColors.teal),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                live ? 'STOP' : 'START',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: live ? BinnacleColors.orange : BinnacleColors.tealBright,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAdjustHandle extends StatelessWidget {
  final ControlChannelService control;
  final String triggerMode;
  final CaptureState capture;
  const _QuickAdjustHandle({required this.control, required this.triggerMode, required this.capture});

  static const _modes = ['rider', 'gps', 'swimmer', 'onboard'];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openSheet(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: BinnacleColors.navy,
          border: Border.all(color: BinnacleColors.offWhite.withValues(alpha: 0.09)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quick adjust', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('Change mode & timing without leaving the water',
                      style: TextStyle(fontSize: 10.5, color: BinnacleColors.slate)),
                ],
              ),
            ),
            Text(
              '${triggerMode.toUpperCase()} · −${capture.preRollSeconds}/+${capture.postRollSeconds}',
              style: BinnacleTheme.mono(size: 10.5, color: BinnacleColors.tealBright),
            ),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showGlassBottomSheet(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: BinnacleColors.slateDim, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Text('Trigger mode', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('What tells Vision to start recording a pass',
                style: TextStyle(fontSize: 11, color: BinnacleColors.slate)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _modes
                  .map((m) => ChoiceChip(
                        label: Text(m),
                        selected: m == triggerMode,
                        onSelected: (_) {
                          _CaptureScreenState._send(() => control.setTriggerMode(m, actor: 'levi'));
                          Navigator.of(sheetContext).pop();
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'Pre-roll ${capture.preRollSeconds}s · post-roll ${capture.postRollSeconds}s — set per preset.',
              style: TextStyle(fontSize: 10.5, color: BinnacleColors.slateDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArmSwitchRow extends StatelessWidget {
  final ControlChannelService control;
  final CaptureState capture;
  const _ArmSwitchRow({required this.control, required this.capture});

  @override
  Widget build(BuildContext context) {
    final pending = control.isPending('arm') || control.isPending('disarm');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Armed'),
      subtitle: Text(capture.armed ? 'Tracking active on Vision' : 'Tracking paused',
          style: TextStyle(color: BinnacleColors.slate)),
      trailing: pending
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Switch(
              value: capture.armed,
              onChanged: (v) => _CaptureScreenState._send(
                  () => v ? control.arm(actor: 'levi') : control.disarm(actor: 'levi')),
            ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  final SafetyState safety;
  const _SafetyCard({required this.safety});

  static (Color, Color) _readinessColors(SafetyReadiness r) => switch (r) {
        SafetyReadiness.operational => (BinnacleColors.tealBright, BinnacleColors.tealBright),
        SafetyReadiness.degraded => (BinnacleColors.amber, BinnacleColors.amber),
        SafetyReadiness.faulted => (BinnacleColors.orange, BinnacleColors.orange),
        SafetyReadiness.unknown => (BinnacleColors.slate, BinnacleColors.slateDim),
      };

  Widget _readinessBadge(SafetyReadiness r) {
    final (fg, border) = _readinessColors(r);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border.withValues(alpha: 0.4)),
      ),
      child: Text(r.label, style: BinnacleTheme.mono(size: 8.5, color: fg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: BinnacleColors.navy, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.shield_outlined, size: 16, color: BinnacleColors.tealBright),
            const SizedBox(width: 8),
            Text('Safety', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            // LOCKED is the non-disableable POLICY (always true, by design —
            // see SafetyState's class doc). It is deliberately never driven
            // by readiness below: a faulted sensor doesn't unlock the
            // policy, it just means the badges beneath say so honestly.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BinnacleColors.tealBright.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('LOCKED', style: BinnacleTheme.mono(size: 9, color: BinnacleColors.tealBright)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Fall detection and man-overboard alert are always on. '
            'No disable command exists in the control protocol.',
            style: TextStyle(color: BinnacleColors.slate, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          // Readiness is the SEPARATE, authoritative question of whether the
          // service is actually working right now, per Core — unknown
          // whenever Core hasn't reported it, never assumed operational.
          Row(children: [
            const Text('Fall detection', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            _readinessBadge(safety.fallDetectionReadiness),
            const SizedBox(width: 14),
            const Text('MOB alert', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            _readinessBadge(safety.mobAlertReadiness),
          ]),
        ],
      ),
    );
  }
}
