import 'package:shared_preferences/shared_preferences.dart';

class AppForegroundStatePreference {
  const AppForegroundStatePreference();

  static const String _appActiveKey = 'isAppActive';
  static const String _appActiveAtMsKey = 'isAppActiveAtMs';
  static const Duration appActiveLease = Duration(minutes: 2);

  bool isAppForegroundActive(SharedPreferences prefs) {
    if (!(prefs.getBool(_appActiveKey) ?? false)) return false;
    final activeAtMs = prefs.getInt(_appActiveAtMsKey);
    if (activeAtMs == null) return false;
    final ageMs = DateTime.now().millisecondsSinceEpoch - activeAtMs;
    return ageMs >= 0 && ageMs <= appActiveLease.inMilliseconds;
  }

  Future<void> persistAppForegroundState(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appActiveKey, active);
    if (active) {
      await prefs.setInt(
        _appActiveAtMsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove(_appActiveAtMsKey);
    }
  }
}
