import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/wake_entry.dart';
import '../../core/models/trick_entry.dart';
import '../../core/models/fall_entry.dart';
import 'king_of_wake_screen.dart';
import 'top_tricks_screen.dart';
import 'best_falls_screen.dart';
import 'riders_screen.dart';
import '../theme/binnacle_theme.dart';

/// Compete hub — reached from the bottom nav. Pushes to each of the four
/// leaderboards. Same navigation pattern already used in settings_screen
/// .dart (ListTile -> Navigator.push), not a new pattern invented for this
/// screen.
class CompeteScreen extends StatelessWidget {
  const CompeteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final destinations = [
      (
        'King of Wake', 'GPS-verified speed leaderboard, surf and ramp',
        Icons.speed,
        () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => KingOfWakeScreen(repository: context.read<WakeRepository>()))),
      ),
      (
        'Top Tricks', 'Community-voted trick leaderboard',
        Icons.auto_awesome,
        () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TopTricksScreen(repository: context.read<TrickRepository>()))),
      ),
      (
        'Best Falls', 'Submitted from real Vision/phone footage',
        Icons.videocam_outlined,
        () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BestFallsScreen(repository: context.read<FallRepository>()))),
      ),
      (
        'Riders', 'Season standings across all three',
        Icons.leaderboard_outlined,
        () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RidersScreen(
                  wake: context.read<WakeRepository>(),
                  trick: context.read<TrickRepository>(),
                  fall: context.read<FallRepository>(),
                ))),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Compete')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: destinations
            .map((d) => Card(
                  color: BinnacleColors.navy,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Icon(d.$3, color: BinnacleColors.tealBright),
                    title: Text(d.$1),
                    subtitle: Text(d.$2, style: const TextStyle(fontSize: 11.5)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: d.$4,
                  ),
                ))
            .toList(),
      ),
    );
  }
}
