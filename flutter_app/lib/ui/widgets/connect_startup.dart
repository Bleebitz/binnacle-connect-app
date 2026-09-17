import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Presentation around the existing Navigator, never a replacement route.
/// Required local startup runs concurrently; an unavailable Core is not a
/// startup failure and must not prevent reaching the offline/pairing UI.
class ConnectStartup extends StatefulWidget {
  const ConnectStartup(
      {super.key, required this.initialize, required this.child});

  static const minimumDuration = Duration(milliseconds: 3500);
  static const transitionDuration = Duration(milliseconds: 400);
  static const backgroundAsset =
      'assets/branding/connect_splash_background.png';
  static const logoAsset = 'assets/branding/binnacle_logo_transparent.png';

  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<ConnectStartup> createState() => _ConnectStartupState();
}

class _ConnectStartupState extends State<ConnectStartup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  Timer? _minimumTimer;
  Timer? _transitionTimer;
  bool _loadingAssets = false;
  bool _assetsReady = false;
  bool _ready = false;
  bool _minimumElapsed = false;
  bool _leaving = false;
  bool _finished = false;
  bool _failed = false;
  bool _assetFailed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await widget.initialize();
      if (!mounted) return;
      _ready = true;
      _leaveIfReady();
    } catch (_) {
      // Do not expose storage exceptions or credentials in UI/logs, and do
      // not quietly treat failed session restoration as an unpaired session.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadingAssets) {
      _loadingAssets = true;
      _loadAssets();
    }
  }

  Future<void> _loadAssets() async {
    var failed = false;
    await Future.wait([
      for (final asset in [
        ConnectStartup.backgroundAsset,
        ConnectStartup.logoAsset
      ])
        precacheImage(AssetImage(asset), context,
            onError: (error, stack) => failed = true),
    ]);
    if (!mounted) return;
    if (failed) {
      setState(() => _assetFailed = true);
      return;
    }
    setState(() => _assetsReady = true);
    // Start the minimum only after decoded artwork has reached a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
      _minimumTimer = Timer(ConnectStartup.minimumDuration, () {
        _minimumElapsed = true;
        _leaveIfReady();
      });
    });
  }

  void _leaveIfReady() {
    if (!_ready || !_minimumElapsed || _leaving || !mounted) return;
    setState(() => _leaving = true);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : ConnectStartup.transitionDuration;
    _transitionTimer = Timer(duration, () {
      if (mounted) setState(() => _finished = true);
    });
  }

  void _retry() {
    final retryAssets = _assetFailed;
    final retryInitialization = _failed;
    setState(() {
      _failed = false;
      _assetFailed = false;
    });
    if (retryAssets) _loadAssets();
    if (retryInitialization) _initialize();
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    _transitionTimer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    // Keep the routed application mounted, including incoming route changes.
    // Input, focus and accessibility cannot reach it until the fade finishes.
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: !_finished,
          child: ExcludeFocus(
            excluding: !_finished,
            child: IgnorePointer(ignoring: !_finished, child: widget.child),
          ),
        ),
        if (!_finished)
          Positioned.fill(
            child: BlockSemantics(
              child: AnimatedOpacity(
                opacity: _leaving ? 0 : 1,
                duration: reducedMotion
                    ? Duration.zero
                    : ConnectStartup.transitionDuration,
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle.light.copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: const Color(0xFF020D1C),
                    systemNavigationBarDividerColor: Colors.transparent,
                  ),
                  child: Material(
                    color: const Color(0xFF020D1C),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(ConnectStartup.backgroundAsset,
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            errorBuilder: (context, error, stack) =>
                                const SizedBox.shrink()),
                        SafeArea(
                          child: LayoutBuilder(builder: (context, constraints) {
                            final width = math.min(
                                360.0,
                                math.min(constraints.maxWidth * .78,
                                    constraints.maxHeight * .48));
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_assetsReady)
                                    FadeTransition(
                                      opacity: _entrance,
                                      child: ScaleTransition(
                                        scale: Tween(begin: .94, end: 1.0)
                                            .animate(CurvedAnimation(
                                                parent: _entrance,
                                                curve: Curves.easeOutCubic)),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Stack(children: [
                                              // A narrow, quiet edge light keeps the original
                                              // navy lettering legible without recoloring it.
                                              ExcludeSemantics(
                                                  child: ImageFiltered(
                                                imageFilter:
                                                    ui.ImageFilter.blur(
                                                        sigmaX: 1.5,
                                                        sigmaY: 1.5),
                                                child: Image.asset(
                                                    ConnectStartup.logoAsset,
                                                    width: width,
                                                    fit: BoxFit.contain,
                                                    color: const Color(
                                                        0x887AB6C7)),
                                              )),
                                              Image.asset(
                                                  ConnectStartup.logoAsset,
                                                  width: width,
                                                  fit: BoxFit.contain,
                                                  semanticLabel:
                                                      'Binnacle Marine Systems'),
                                            ]),
                                            const SizedBox(height: 18),
                                            const Text('CONNECT',
                                                style: TextStyle(
                                                    fontFamily: 'sans-serif',
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w500,
                                                    letterSpacing: 5,
                                                    color: Color(0xFFE5FAFF))),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (_failed || _assetFailed) ...[
                                    const SizedBox(height: 20),
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 24),
                                      child: Text(
                                          'Could not start Connect. Please try again.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14)),
                                    ),
                                    TextButton(
                                        onPressed: _retry,
                                        child: const Text('Retry')),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
