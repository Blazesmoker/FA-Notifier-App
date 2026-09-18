import 'package:shared_preferences/shared_preferences.dart';

class PrivacySettingsPreference {
  const PrivacySettingsPreference();

  static const analyticsEpochKey = 'backgroundAnalyticsConsentEpoch';
  static const crashlyticsEpochKey = 'backgroundCrashlyticsConsentEpoch';
  static const analyticsEnabledKey = 'firebaseAnalyticsEnabled';
  static const crashlyticsEnabledKey = 'firebaseCrashlyticsEnabled';
  static const consentShownKey = 'privacyConsentShown';

  Future<bool> loadAnalyticsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(analyticsEnabledKey) ?? false;
  }

  Future<bool> loadCrashlyticsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(crashlyticsEnabledKey) ?? false;
  }

  Future<bool> loadConsentShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(consentShownKey) ?? false;
  }

  Future<void> saveAnalyticsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!value) {
      await prefs.setInt(analyticsEpochKey, (prefs.getInt(analyticsEpochKey) ?? 0) + 1);
    }
    await prefs.setBool(analyticsEnabledKey, value);
  }

  Future<void> saveCrashlyticsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!value) {
      await prefs.setInt(crashlyticsEpochKey, (prefs.getInt(crashlyticsEpochKey) ?? 0) + 1);
    }
    await prefs.setBool(crashlyticsEnabledKey, value);
  }

  Future<void> saveConsentShown(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(consentShownKey, value);
  }
}