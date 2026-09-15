import 'package:flutter/material.dart';
import '../../core/models/wake_entry.dart';
import '../../core/models/trick_entry.dart';
import '../../core/models/fall_entry.dart';
import '../../core/models/riders_leaderboard.dart';
import '../theme/binnacle_theme.dart';

/// Riders — cumulative season points. Read-only: this screen has no entry
/// sheet and no repository of its own, because RidersLeaderboard is a pure
/// computation over the other three (see that file's module comment for why
/// that's a deliberate design choice, not a missing feature).
class RidersScreen extends StatelessWidget {
  final WakeRepository wake;
  final TrickRepository trick;
  final FallRepository fall;
  const RidersScreen({super.key, required this.wake, required this.trick, required this.fall});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Riders — season standings')),
      body: AnimatedBuilder(
        animation: Listenable.merge([wake, trick, fall]),
        builder: (context, _) {
          final standings = RidersLeaderboard.compute(wake: wake, trick: trick, fall: fall);
          if (standings.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text('No entries yet across King of Wake, Top Tricks, or Best Falls.',
                    textAlign: TextAlign.center, style: TextStyle(color: BinnacleColors.slate)),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: standings.length,
            itemBuilder: (_, i) {
              final s = standings[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: BinnacleColors.navy, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Container(
                    width: 30, height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == 0 ? BinnacleColors.amber : BinnacleColors.navyRaised,
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}', style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: i == 0 ? BinnacleColors.navyDeep : BinnacleColors.offWhite)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.riderName, style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '${s.wakeEntries} wake · ${s.trickEntries} tricks · ${s.fallEntries} falls',
                          style: BinnacleTheme.mono(size: 10),
                        ),
                      ],
                    ),
                  ),
                  Text('${s.totalPoints} pts',
                      style: BinnacleTheme.mono(size: 13, color: BinnacleColors.tealBright, weight: FontWeight.w700)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
