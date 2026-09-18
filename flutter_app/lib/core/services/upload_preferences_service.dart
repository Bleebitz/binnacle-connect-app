// Real, persisted Wi-Fi-only / Wi-Fi-or-cellular preference for the
// offline upload queue (see upload_queue_service.dart). Separate from
// MediaUploadService (which answers "can uploads ever succeed") — this
// answers "should an upload attempt start right now, on this network."

import 'package:shared_preferences/shared_preferences.dart';

enum UploadNetworkPreference { wifiOnly, wifiOrCellular }

class UploadPreferencesService {
  static const _key = 'upload_network_preference_v1';

  Future<UploadNetworkPreference> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return UploadNetworkPreference.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => UploadNetworkPreference.wifiOnly,
    );
  }

  Future<void> save(UploadNetworkPreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, preference.name);
  }
}
