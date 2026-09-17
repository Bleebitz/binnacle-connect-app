import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/binnacle_theme.dart';
import 'binnacle_background.dart';

/// Wraps the app's existing Navigator (via MaterialApp.builder) rather than
/// replacing it — [child] is the real, already-routed app, mounted for the
/// whole lifetime of this widget, never swapped out. That is what lets an
/// incoming route (deep link, programmatic navigation before startup
/// finishes) survive the splash instead of being lost to a widget swap.
///
/// Real startup work — currently just [PairingService.restore()], a genuine
/// Keychain/Keystore read — is started immediately and runs concurrently
/// with the splash presentation, not sequenced after it. Leaving requires
/// BOTH that work to succeed AND a minimum visible-splash floor to elapse;
/// the floor only starts counting once the brand artwork has actually
/// decoded and reached a frame, so asset-decode time is never counted as
/// part of the "visible" 3.5s. A failed [initialize] shows a visible retry
/// control instead of silently swallowing the error — see main.dart for why
/// that used to be wrong (a `catchError((_) {})` that made a real,
/// previously-latent restore failure invisible).
class ConnectStartup extends StatefulWidget {
  const ConnectStartup(
      {super.key, required this.initialize, required this.child});

  static const minimumDuration = Duration(milliseconds: 3500);
  static const transitionDuration = Duration(milliseconds: 450);
  static const backgroundAsset = 'assets/backgrounds/wave_glow.png';
  static const logoAsset = 'assets/brand/binnacle_logo.png';

  /// Test-only escape hatch (same idiom as Flutter's own `debugDisableShadows`
  /// etc.) — skips the entire readiness gate and animation, finishing
  /// immediately. Widget tests that only need to get past the splash to
  /// exercise the rest of the app (not verify splash behavior itself) set
  /// this in `setUp()` instead of awaiting real image decode via
  /// `WidgetTester.runAsync` — see test/support/connect_startup_test_utils.dart.
  /// Always false outside tests; never read in release builds' hot paths.
  static bool debugSkipForTesting = false;

  /// Required local startup work. An unreachable Core is deliberately NOT a
  /// startup failure here — that's a separate, already-handled runtime state
  /// (offline/pairing UI), not something that should ever block reaching it.
  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<ConnectStartup> createState() => _ConnectStartupState();
}

class _ConnectStartupState extends State<ConnectStartup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
  );
  late final Animation<double> _logoScale = Tween<double>(begin: 0.88, end: 1.0)
      .animate(CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
  ));
  late final Animation<double> _wordmarkFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
  );

  Timer? _minimumTimer;
  bool _assetsLoading = false;
  bool _assetsReady = false;
  bool _assetsFailed = false;
  bool _initReady = false;
  bool _initFailed = false;
  bool _minimumElapsed = false;
  bool _leaving = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    // _entrance is a lazily-created `late final` field (only otherwise
    // touched inside _loadAssets(), which debugSkipForTesting below never
    // reaches) — force it to materialize now, while this element is still
    // active. dispose() unconditionally disposes it; without this, skipping
    // straight to _finished=true means dispose() is the very first access,
    // lazily constructing the AnimationController (and its ticker, which
    // needs to look up an ancestor) at a point where the element is already
    // being torn down — a real "deactivated widget's ancestor" crash.
    _entrance.duration; // ignore: unnecessary_statements
    if (ConnectStartup.debugSkipForTesting) {
      _finished = true;
      return;
    }
    _runInitialize();
  }

  Future<void> _runInitialize() async {
    try {
      await widget.initialize();
      if (!mounted) return;
      setState(() => _initReady = true);
      _leaveIfReady();
    } catch (_) {
      // Visible retry, not a swallowed error — and no exception detail is
      // surfaced (this may be a storage/credential failure).
      if (mounted) setState(() => _initFailed = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ConnectStartup.debugSkipForTesting) return;
    if (!_assetsLoading) {
      _assetsLoading = true;
      _loadAssets();
    }
  }

  Future<void> _loadAssets() async {
    var failed = false;
    await Future.wait([
      for (final asset in [
        ConnectStartup.backgroundAsset,
        ConnectStartup.logoAsset,
      ])
        precacheImage(AssetImage(asset), context,
            onError: (error, stack) => failed = true),
    ]);
    if (!mounted) return;
    if (failed) {
      setState(() => _assetsFailed = true);
      return;
    }
    setState(() => _assetsReady = true);
    // The minimum-visible-duration floor starts only once decoded artwork
    // has actually reached a frame — decode time must never count toward
    // "3.5 seconds visible."
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
    if (!_initReady || !_minimumElapsed || _leaving || !mounted) return;
    setState(() => _leaving = true);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : ConnectStartup.transitionDuration;
    Timer(duration, () {
      if (mounted) setState(() => _finished = true);
    });
  }

  void _retry() {
    final retryAssets = _assetsFailed;
    final retryInitialization = _initFailed;
    setState(() {
      _assetsFailed = false;
      _initFailed = false;
    });
    if (retryAssets) _loadAssets();
    if (retryInitialization) _runInitialize();
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // The real app, mounted for this widget's entire lifetime. Input,
        // focus and semantics can't reach it until the splash has finished
        // fading out — but it is never rebuilt, never torn down, and any
        // route pushed onto it while the splash is up (e.g. a deep link)
        // survives untouched underneath.
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
                child: _SplashVisual(
                  assetsReady: _assetsReady,
                  failed: _initFailed || _assetsFailed,
                  onRetry: _retry,
                  logoFade: _logoFade,
                  logoScale: _logoScale,
                  wordmarkFade: _wordmarkFade,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SplashVisual extends StatelessWidget {
  const _SplashVisual({
    required this.assetsReady,
    required this.failed,
    required this.onRetry,
    required this.logoFade,
    required this.logoScale,
    required this.wordmarkFade,
  });

  final bool assetsReady;
  final bool failed;
  final VoidCallback onRetry;
  final Animation<double> logoFade;
  final Animation<double> logoScale;
  final Animation<double> wordmarkFade;

  @override
  Widget build(BuildContext context) {
    return BinnacleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive, not fixed: bounded by both available width and
              // height so the (now much larger) mark neither clips on a
              // small/narrow phone nor overruns a short landscape viewport.
              final logoWidth = math.min(
                300.0,
                math.min(
                  constraints.maxWidth * 0.68,
                  constraints.maxHeight * 0.34,
                ),
              );
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (assetsReady)
                      FadeTransition(
                        opacity: logoFade,
                        child: ScaleTransition(
                          key: const ValueKey('connect-startup-logo-scale'),
                          scale: logoScale,
                          child: _GlowingLogo(width: logoWidth),
                        ),
                      ),
                    const SizedBox(height: 22),
                    if (assetsReady)
                      FadeTransition(
                        opacity: wordmarkFade,
                        child: Text(
                          'CONNECT',
                          style: _splashMono(
                            size: 13,
                            color: BinnacleColors.tealBright,
                            weight: FontWeight.w600,
                          ).copyWith(letterSpacing: 7),
                        ),
                      ),
                    if (failed) ...[
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Could not start Connect. Please try again.',
                          textAlign: TextAlign.center,
                          style: _splashMono(size: 12, color: BinnacleColors.slate),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: onRetry,
                        child: Text('RETRY',
                            style: _splashMono(
                                size: 12,
                                color: BinnacleColors.tealBright,
                                weight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Deliberately NOT BinnacleTheme.mono() (GoogleFonts JetBrains Mono) —
/// the splash is the app's most latency-sensitive moment (nothing else has
/// rendered yet) and must never depend on a font network fetch succeeding.
/// The rest of the app already uses GoogleFonts once it's actually running;
/// this is specific to the pre-first-paint splash overlay only.
TextStyle _splashMono({required double size, required Color color, FontWeight? weight}) {
  return TextStyle(
    fontFamily: 'monospace',
    fontSize: size,
    color: color,
    fontWeight: weight ?? FontWeight.w500,
  );
}

/// The sharp logo, unmodified, with a restrained cyan/teal glow composited
/// as a separate layer behind it — never redrawn or recolored itself. Two
/// tinted, blurred duplicates of the same asset sit underneath: a small,
/// thin-blur "edge light" duplicate (reads as contrast right at the
/// shield/lettering edges) and a larger, heavily-blurred "diffuse halo"
/// duplicate (a soft ambient glow, not a hard outline). Both use the
/// image's own alpha shape (via `BlendMode.srcIn`) so the glow traces the
/// actual silhouette — shield, needle, and the BINNACLE / MARINE SYSTEMS
/// lettering baked into the artwork — rather than a generic rectangle.
/// No pulsing, no looping motion: this is a static composite, matched to
/// the rest of the entrance's restrained, one-shot animation.
class _GlowingLogo extends StatelessWidget {
  const _GlowingLogo({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          ExcludeSemantics(
            child: Opacity(
              opacity: 0.30,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Image.asset(
                  ConnectStartup.logoAsset,
                  width: width * 1.1,
                  fit: BoxFit.contain,
                  color: BinnacleColors.tealBright,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
            ),
          ),
          ExcludeSemantics(
            child: Opacity(
              opacity: 0.5,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: Image.asset(
                  ConnectStartup.logoAsset,
                  width: width * 1.015,
                  fit: BoxFit.contain,
                  color: BinnacleColors.tealBright,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
            ),
          ),
          Image.asset(
            ConnectStartup.logoAsset,
            width: width,
            fit: BoxFit.contain,
            semanticLabel: 'Binnacle Marine Systems',
          ),
        ],
      ),
    );
  }
}
