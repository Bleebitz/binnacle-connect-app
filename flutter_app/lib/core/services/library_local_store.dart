// Persists phone-imported Library entries across restarts. Only clips
// with a real [Clip.localPath] are ever written here — demo-seeded and
// Core-fetched clips are reconstructed fresh every launch (from seedDemo()
// or a real Core fetch respectively) and never belong in this store, so a
// stale local copy can never drift from what Core/demo actually reports.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/clip.dart';

abstract class LibraryLocalStore {
  Future<List<Clip>> loadImported();
  Future<void> saveImported(List<Clip> clips);
}

class SharedPreferencesLibraryLocalStore implements LibraryLocalStore {
  static const _key = 'library_imported_clips_v1';

  @override
  Future<List<Clip>> loadImported() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Clip.fromLocalJson)
          .toList(growable: false);
    } catch (_) {
      // A corrupted local store must never crash startup — worst case,
      // previously-imported entries are lost, not the app.
      return const [];
    }
  }

  @override
  Future<void> saveImported(List<Clip> clips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(clips.map((c) => c.toJson()).toList()));
  }
}
