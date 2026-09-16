import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    final crewRepo = context.watch<CrewRepository>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Community'),
          bottom: const TabBar(tabs: [Tab(text: 'Crew'), Tab(text: 'Compete')]),
        ),
        body: TabBarView(children: [
          CrewScreen(repository: crewRepo),
          const CompeteScreen(),
        ]),
      ),
    );
  }
}
