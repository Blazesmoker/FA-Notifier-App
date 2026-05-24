import 'package:shared_preferences/shared_preferences.dart';

class PendingNavigationStore {
  static const _pendingNavigationKey = 'pending_navigation';

  Future<String?> loadPayload({bool reload = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (reload) {
      await prefs.reload();
    }
    return prefs.getString(_pendingNavigationKey);
  }

  Future<void> clearPayload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingNavigationKey);
  }
}
