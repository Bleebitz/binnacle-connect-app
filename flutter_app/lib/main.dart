import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_config.dart';
import 'core/services/control_channel_service.dart';
import 'core/services/telemetry_socket.dart';
import 'core/services/pairing_service.dart';
import 'core/models/vessel_state.dart'; // LinkStatus lives here — used below
import 'ui/screens/capture_screen.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/crew_screen.dart';
import 'core/models/trick_entry.dart';
import 'core/models/fall_entry.dart';
import 'core/models/wake_entry.dart'; // WakeRepository — no longer re-exported via compete_screen.dart
import 'ui/screens/compete_hub_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/theme/binnacle_theme.dart';

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
            if (AppConfig.mode == AppMode.core && service.status == LinkStatus.simulated) {
              service.connect(
                deviceId: 'vision-0001',
                endpoint: AppConfig.coreWebSocketEndpoint(),
              );
            }
            return service;
          },
        ),

        ChangeNotifierProvider(create: (_) => TelemetrySocket()..startSimulated()),
        ChangeNotifierProvider(create: (_) => ClipRepository()..seedDemo()),
        ChangeNotifierProvider(create: (_) => CrewRepository()),
        ChangeNotifierProvider(create: (_) => WakeRepository()),
        ChangeNotifierProvider(create: (_) => TrickRepository()),
        ChangeNotifierProvider(create: (_) => FallRepository()),
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
    final crewRepo = context.watch<CrewRepository>();

    final screens = [
      const CaptureScreen(),
      LibraryScreen(repository: clipRepo),
      CrewScreen(repository: crewRepo),
      const CompeteScreen(),
      const SettingsScreen(),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: BinnacleColors.navyDeep,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.videocam_outlined), label: 'Capture'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Crew'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), label: 'Compete'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
