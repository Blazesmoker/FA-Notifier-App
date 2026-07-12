import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/features/notifications/domain/pending_navigation_repository.dart';

class PendingNavigationStore implements PendingNavigationRepository {
  const PendingNavigationStore();

  static const _pendingNavigationKey = 'pending_navigation';
  static const _lastHandledPayloadKey = 'last_handled_payload';

  @override
  Future<String?> loadPayload({bool reload = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (reload) {
      await prefs.reload();
    }
    return prefs.getString(_pendingNavigationKey);
  }

  @override
  Future<void> clearPayload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingNavigationKey);
  }

  @override
  Future<void> savePayload(String payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingNavigationKey, payload);
  }

  @override
  Future<void> recordHandledPayload(String payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastHandledPayloadKey, payload);
  }
}
