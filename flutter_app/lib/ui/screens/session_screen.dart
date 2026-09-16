import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/clip.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/empty_state.dart';
import 'library_screen.dart' show ClipRepository;

/// Session — a coherent day-on-the-water timeline: passes, automatic
/// highlights, falls, and rider changes as one chronological story, not
/// scattered across a grid. Per BIN-32, this was "largely missing today"
/// and is meant to be one of Connect's real differentiators.
///
/// v1 scope, stated honestly: there's no real session-boundary tracking
/// yet (a Session model with its own start/end, spanning a pairing/arm
/// cycle) — that's genuine future work once Core exists to anchor it to.
/// This shows every captured clip as one running timeline ("today's
/// session"), which is exactly what a single day on the water looks like
/// today, without inventing session boundaries the app can't actually
/// detect yet.
class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final clips = context.watch<ClipRepository>().clips;
    final sorted = [...clips]..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Session')),
      body: sorted.isEmpty
          ? const BinnacleEmptyState(
              icon: Icons.timeline_outlined,
              title: 'No session yet',
              subtitle: 'Arm Track and start capturing —\nyour passes, highlights, and falls show up here.',
              accent: BinnacleColors.tealBright,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SessionSummary(clips: sorted),
                const SizedBox(height: 16),
                ..._withDayHeaders(sorted).map((entry) => entry.$1 != null
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 12),
                        child: Text(entry.$1!,
                            style: BinnacleTheme.mono(size: 10.5, color: BinnacleColors.slate)),
                      )
                    : _TimelineEntry(clip: entry.$2!)),
              ],
            ),
    );
  }

  /// Interleaves a day-label header before the first entry of each day —
  /// simple enough not to need its own model, and the only grouping a
  /// single running timeline actually needs.
  List<(String?, Clip?)> _withDayHeaders(List<Clip> sorted) {
    final out = <(String?, Clip?)>[];
    String? lastDay;
    for (final c in sorted) {
      final day = _dayLabel(c.capturedAt);
      if (day != lastDay) {
        out.add((day, null));
        lastDay = day;
      }
      out.add((null, c));
    }
    return out;
  }

  static String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final isToday = t.year == now.year && t.month == now.month && t.day == now.day;
    if (isToday) return 'TODAY';
    return '${t.month}/${t.day}/${t.year}'.toUpperCase();
  }
}

class _SessionSummary extends StatelessWidget {
  final List<Clip> clips;
  const _SessionSummary({required this.clips});

  @override
  Widget build(BuildContext context) {
    final highlights = clips.where((c) => c.kind == ClipKind.highlight).length;
    final falls = clips.where((c) => c.kind == ClipKind.fall).length;
    final photos = clips.where((c) => c.kind == ClipKind.photo).length;
    final riders = clips.map((c) => c.riderId).toSet().length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BinnacleColors.navyRaised, BinnacleColors.navy],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BinnacleColors.offWhite.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          _Stat(count: highlights, label: 'HIGHLIGHTS'),
          _Stat(count: falls, label: 'FALLS'),
          _Stat(count: photos, label: 'PHOTOS'),
          _Stat(count: riders, label: 'RIDERS'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int count;
  final String label;
  const _Stat({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$count',
              style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w700, fontSize: 20, color: BinnacleColors.tealBright)),
          const SizedBox(height: 2),
          Text(label, style: BinnacleTheme.mono(size: 8.5, color: BinnacleColors.slateDim)),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final Clip clip;
  const _TimelineEntry({required this.clip});

  @override
  Widget build(BuildContext context) {
    final (icon, accent) = switch (clip.kind) {
      ClipKind.fall => (Icons.warning_amber_rounded, BinnacleColors.orange),
      ClipKind.photo => (Icons.photo_camera_outlined, BinnacleColors.tealBright),
      ClipKind.highlight => (Icons.videocam_outlined, BinnacleColors.amber),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, size: 15, color: accent),
              ),
              Container(width: 1.5, height: 22, color: BinnacleColors.offWhite.withValues(alpha: 0.08)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clip.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '${_riderLabel(clip.riderId)} · ${_timeLabel(clip.capturedAt)}'
                  '${clip.duration > Duration.zero ? ' · ${clip.duration.inSeconds}s' : ''}',
                  style: BinnacleTheme.mono(size: 10, color: BinnacleColors.slate),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _riderLabel(String riderId) =>
      riderId.isEmpty ? 'Unknown rider' : riderId[0].toUpperCase() + riderId.substring(1);

  static String _timeLabel(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}
