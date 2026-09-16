// App mode contract — compile-time only (dart-define), never a runtime
// toggle, so a demo build can't accidentally flip into talking to a real
// Core and a Core build can't silently fall back to fake data.
//
//   flutter run --dart-define=BINNACLE_APP_MODE=demo   (default if omitted)
//   flutter run --dart-define=BINNACLE_APP_MODE=core \
//               --dart-define=BINNACLE_CORE_URL=https://your-core-host
//
// demo: never opens a network connection to a Core. Stays LinkStatus
//       .simulated permanently — see main.dart's ControlChannelService
//       wiring, which only calls connect() in core mode. This is the fix
//       for a real bug: before this existed, "simulated" mode still tried
//       to open wss://core.local and immediately failed, so the UI showed
//       "Offline — still recording" instead of an honest "Simulated"
//       status on every single demo run.
// core: requires BINNACLE_CORE_URL. Missing it is a configuration error —
//       main() refuses to start the real app rather than quietly
//       defaulting back to demo mode, which would hide a broken deploy.
enum AppMode { demo, core }

class AppConfig {
  static const String _modeString = String.fromEnvironment('BINNACLE_APP_MODE', defaultValue: 'demo');
  static const String coreUrl = String.fromEnvironment('BINNACLE_CORE_URL');

  static AppMode get mode => _modeString == 'core' ? AppMode.core : AppMode.demo;
  static bool get isDemo => mode == AppMode.demo;

  /// True only when core mode was requested without a URL — the one
  /// configuration state that must refuse to boot rather than degrade.
  static bool get isMisconfigured => mode == AppMode.core && coreUrl.isEmpty;

  /// Core's WSS endpoint, derived from the configured base URL. Accepts
  /// http(s) (as shown in ops docs) or ws(s) directly.
  static Uri coreWebSocketEndpoint() {
    final uri = Uri.parse(coreUrl);
    final scheme = switch (uri.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      _ => uri.scheme,
    };
    return uri.replace(scheme: scheme, path: '/spotter/ws');
  }
}
