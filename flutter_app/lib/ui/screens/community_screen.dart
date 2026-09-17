import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import 'package:provider/provider.dart';
import '../widgets/binnacle_background.dart';
import 'crew_screen.dart';
import 'compete_hub_screen.dart';

/// Community — Crew and the four leaderboards (King of Wake, Top Tricks,
/// Best Falls, Riders) live here, one level down from the primary bottom
/// nav rather than as separate top-level tabs. Per the BIN-32 product
/// reorganization: Crew and Compete used to sit at the same navigational
/// weight as actually operating the camera (Capture/Live), which made
/// Connect read as a collection of bolted-together features rather than
/// one coherent "ride → track → review → share/compete" story. Nothing in
/// either screen changed — CrewScreen and CompeteScreen are now body-only
/// widgets (no Scaffold/AppBar of their own) embedded as tabs here.
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isDemo) {
      return BinnacleBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text('Community')),
          body: const Center(
              child: Text(
                  'Community and Compete preview remains available in Demo.\n'
                  'Live integration follows the Core ride experience.')),
        ),
      );
    }
    final crewRepo = context.watch<CrewRepository>();
    return BinnacleBackground(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Community'),
            bottom:
                const TabBar(tabs: [Tab(text: 'Crew'), Tab(text: 'Compete')]),
          ),
          body: TabBarView(children: [
            CrewScreen(repository: crewRepo),
            const CompeteScreen(),
          ]),
        ),
      ),
    );
  }
}
