import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_config.dart';
import 'core/services/control_channel_service.dart';
import 'core/services/mob_alert_state.dart';
import 'core/services/telemetry_socket.dart';
import 'core/services/pairing_service.dart';
import 'core/models/vessel_state.dart'; // LinkStatus lives here — used below
import 'ui/screens/capture_screen.dart';
import 'ui/screens/community_screen.dart';
import 'core/services/media_catalog_service.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/crew_screen.dart';
import 'core/models/trick_entry.dart';
import 'core/models/fall_entry.dart';
import 'core/models/wake_entry.dart'; // WakeRepository — no longer re-exported via compete_screen.dart
import 'ui/screens/my_boat_screen.dart';
import 'ui/screens/session_screen.dart';
import 'ui/theme/binnacle_theme.dart';
import 'core/services/connected_services.dart';
import 'core/services/entitlement_service.dart';
import 'core/services/live_broadcast_service.dart';

void main() {
  // Core mode with no URL is a broken deploy, not a reason to quietly act
  // like a demo — refuse to start the real app so this is loud, not
  // discovered later as "why is it showing fake data on the boat."
  if (AppConfig.isMisconfigured) {
    runApp(const _ConfigErrorApp());
    return;
  }
  runApp(const BinnacleConnectApp());
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: BinnacleTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: BinnacleColors.orange, size: 40),
                const SizedBox(height: 16),
                const Text('Configuration error',
                    style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  'BINNACLE_APP_MODE=core requires BINNACLE_CORE_URL.\n'
                  'Pass both --dart-define flags, or omit APP_MODE to run in demo mode.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BinnacleColors.slate),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BinnacleConnectApp extends StatelessWidget {
  const BinnacleConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // PairingService must exist before ControlChannelService connects,
        // since the credential it holds is what gets attached to the socket.
        // See Connect_Device_Pairing_and_Authorization_Design_v0.1.
        ChangeNotifierProvider(create: (_) => PairingService()..restore()),

        // ProxyProvider so ControlChannelService always has the current
        // PairingService attached, including if pairing state changes after
        // the app has already connected (e.g. role reassigned by the owner).
        ChangeNotifierProxyProvider<PairingService, ControlChannelService>(
          create: (_) => ControlChannelService(),
          update: (context, pairing, control) {
            final service = control ?? ControlChannelService();
            service.attachPairing(pairing);
            // Demo mode must never attempt a network connection — see
            // app_config.dart. It stays LinkStatus.simulated for the whole
            // session, which is the point: an honest "Simulated" badge
            // instead of a connection attempt that immediately fails and
            // shows "Offline" on every single demo run.
            if (AppConfig.mode == AppMode.core && pairing.isPaired && service.status == LinkStatus.offline) {
              service.connect(
                deviceId: pairing.credential!.deviceId,
                endpoint: AppConfig.coreWebSocketEndpoint(),
              );
            }
            return service;
          },
        ),

        ChangeNotifierProvider(create: (_) => MobAlertState()),
        // Only fabricate telemetry in demo mode. A core-mode build with no
        // real telemetry connection yet should show honest zero/default
        // values, not simulated numbers that look like a live boat.
        ChangeNotifierProvider(create: (_) {
          final telemetry = TelemetrySocket();
          if (AppConfig.isDemo) telemetry.startSimulated();
          return telemetry;
        }),
        // ProxyProvider2 so a real Core connection triggers exactly one real
        // catalog fetch — same idempotent-guard pattern as
        // ControlChannelService.connect() above (guard on a "already tried"
        // flag rather than re-triggering every rebuild).
        ChangeNotifierProxyProvider2<PairingService, ControlChannelService, ClipRepository>(
          create: (_) {
            final clips = ClipRepository();
            if (AppConfig.isDemo) clips.seedDemo();
            return clips;
          },
          update: (context, pairing, control, clips) {
            final repo = clips!;
            if (!AppConfig.isDemo &&
                control.hasCurrentState &&
                pairing.credential?.bearerToken != null &&
                !repo.loading &&
                !repo.attemptedLoad) {
              repo.loadFromCore(
                HttpMediaCatalogService(),
                pairing.credential!.deviceId,
                bearerToken: pairing.credential!.bearerToken!,
              );
            }
            return repo;
          },
        ),
        ChangeNotifierProvider(create: (_) => CrewRepository()),
        ChangeNotifierProvider(create: (_) => WakeRepository()),
        ChangeNotifierProvider(create: (_) => TrickRepository()),
        ChangeNotifierProvider(create: (_) => FallRepository()),

        // Connect Live (BIN-38). EntitlementService is the injectable
        // entitlement boundary — StaticEntitlementService always reports
        // Free because no real Binnacle Billing service exists yet (see
        // entitlement_service.dart); this must never be swapped for a
        // hard-coded paid tier here. ConnectedServicesService similarly
        // ships only its honest not-connected/custom-RTMP implementation.
        // Explicit type parameters: the UI reads the ABSTRACT service types
        // (context.watch<EntitlementService>(), <ConnectedServicesService>())
        // so a future real implementation can be swapped in here without
        // touching any consumer — but that only works if the provider is
        // registered under the interface type. Without <EntitlementService>
        // here, ChangeNotifierProvider infers the concrete
        // StaticEntitlementService type from `create`, and every
        // context.watch<EntitlementService>() call throws
        // ProviderNotFoundException.
        ChangeNotifierProvider<EntitlementService>(create: (_) => StaticEntitlementService()),
        ChangeNotifierProvider<ConnectedServicesService>(create: (_) => LocalConnectedServicesService()),
        // ProxyProvider so the demo/Core transport choice follows the same
        // AppConfig.isDemo split as every other service, and so the Core
        // transport gets the SAME ControlChannelService instance (one
        // authenticated socket, not a second connection).
        ChangeNotifierProxyProvider<ControlChannelService, LiveBroadcastService>(
          create: (context) => LiveBroadcastService(
            transport: AppConfig.isDemo
                ? DemoBroadcastTransport()
                : CoreBroadcastTransport(control: context.read<ControlChannelService>()),
            demo: AppConfig.isDemo,
          ),
          update: (context, control, live) => live!,
        ),
      ],
      child: MaterialApp(
        title: 'Binnacle Connect',
        debugShowCheckedModeBanner: false,
        theme: BinnacleTheme.dark(),
        home: const _RootShell(),
      ),
    );
  }
}

class _RootShell extends StatefulWidget {
  const _RootShell();

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final clipRepo = context.watch<ClipRepository>();
    final mobActive = context.watch<MobAlertState>().active;

    // My Boat / Live / Session / Library / Community — reorganized around
    // the actual boating experience (connect → ride → review → share/
    // compete) per BIN-32, instead of Capture/Library/Crew/Compete/Settings
    // giving Crew and Compete the same navigational weight as operating the
    // camera. Settings moved behind My Boat's profile icon; Crew and the
    // four leaderboards moved into Community — see those screens' module
    // comments.
    final screens = [
      MyBoatScreen(onGoLive: () => setState(() => _index = 1)),
      const CaptureScreen(),
      const SessionScreen(),
      LibraryScreen(repository: clipRepo),
      const CommunityScreen(),
    ];

    return Scaffold(
      // A cross-fade + subtle scale between tabs reads far less "flat" than
      // IndexedStack's instant swap, while keeping IndexedStack's actual
      // point: every screen (and the state/timers it owns — recording UI,
      // pairing flow, etc.) stays alive underneath, never rebuilt on switch.
      body: Stack(
        children: [
          for (var i = 0; i < screens.length; i++)
            IgnorePointer(
              ignoring: i != _index,
              child: AnimatedOpacity(
                opacity: i == _index ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: AnimatedScale(
                  scale: i == _index ? 1 : 0.98,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: screens[i],
                ),
              ),
            ),
        ],
      ),
      // Frosted glass (a real backdrop blur, not just a translucent color)
      // plus a tint that shifts toward orange app-wide while a MOB alert is
      // active — chrome that reacts to what's actually happening, on the
      // one surface that's visible no matter which tab you're on.
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            color: mobActive
                ? BinnacleColors.orange.withValues(alpha: 0.16)
                : BinnacleColors.navyDeep.withValues(alpha: 0.72),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              backgroundColor: Colors.transparent,
              indicatorColor: mobActive ? BinnacleColors.orange.withValues(alpha: 0.3) : null,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.directions_boat_outlined), label: 'My Boat'),
                NavigationDestination(icon: Icon(Icons.videocam_outlined), label: 'Live'),
                NavigationDestination(icon: Icon(Icons.timeline_outlined), label: 'Session'),
                NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Library'),
                NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Community'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
