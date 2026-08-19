import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/core/preferences/privacy_settings_preference.dart';

class HomeSessionPreference {
  static const _isLoggedInKey = 'isLoggedIn';

  Future<bool> loadIsLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  Future<void> saveIsLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, value);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final analyticsEnabled =
        prefs.getBool(PrivacySettingsPreference.analyticsEnabledKey);
    final crashlyticsEnabled =
        prefs.getBool(PrivacySettingsPreference.crashlyticsEnabledKey);
    final consentShown =
        prefs.getBool(PrivacySettingsPreference.consentShownKey);
    await prefs.clear();
    if (analyticsEnabled != null) {
      await prefs.setBool(
        PrivacySettingsPreference.analyticsEnabledKey,
        analyticsEnabled,
      );
    }
    if (crashlyticsEnabled != null) {
      await prefs.setBool(
        PrivacySettingsPreference.crashlyticsEnabledKey,
        crashlyticsEnabled,
      );
    }
    if (consentShown != null) {
      await prefs.setBool(
        PrivacySettingsPreference.consentShownKey,
        consentShown,
      );
    }
  }
}
