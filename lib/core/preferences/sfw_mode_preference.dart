import 'package:shared_preferences/shared_preferences.dart';

class SfwModePreference {
  const SfwModePreference();

  static const _sfwEnabledKey = 'sfwEnabled';

  Future<bool> loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sfwEnabledKey) ?? true;
  }

  Future<void> saveSfwEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sfwEnabledKey, value);
  }
}
