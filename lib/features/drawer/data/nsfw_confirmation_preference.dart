import 'package:shared_preferences/shared_preferences.dart';

class NsfwConfirmationPreference {
  static const _disabledKey = 'nsfwConfirmationDisabled';

  Future<bool> loadDisabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_disabledKey) ?? false;
  }

  Future<void> saveDisabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_disabledKey, value);
  }
}
