import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/services/control_channel_service.dart';
import 'core/services/telemetry_socket.dart';
import 'core/services/pairing_service.dart';
import 'core/models/vessel_state.dart'; // LinkStatus lives here — used below
import 'ui/screens/capture_screen.dart';
import 'ui/screens/library_screen.dart';
import 'ui/screens/crew_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/theme/binnacle_theme.dart';

void main() {
  runApp(const BinnacleConnectApp());
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
            if (service.status == LinkStatus.simulated) {
              // Placeholder endpoint. Real value comes from the Core's
              // pairing flow — see PairingTarget.coreHost once a device is
              // actually paired. Until then this stays LinkStatus.simulated.
              service.connect(
                deviceId: 'vision-0001',
                endpoint: Uri.parse('wss://core.local/spotter/ws'),
              );
            }
            return service;
          },
        ),

        ChangeNotifierProvider(create: (_) => TelemetrySocket()..startSimulated()),
        ChangeNotifierProvider(create: (_) => ClipRepository()),
        ChangeNotifierProvider(create: (_) => CrewRepository()),
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
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: BinnacleColors.navyDeep,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.videocam_outlined), label: 'Capture'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Crew'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
