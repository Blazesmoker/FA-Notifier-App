import 'package:flutter/foundation.dart';

import 'package:fanotifier/core/analytics/app_analytics.dart';
import 'package:fanotifier/core/crash_reporting/app_crash_reporter.dart';
import 'package:fanotifier/core/preferences/privacy_settings_preference.dart';

class PrivacySettingsProvider extends ChangeNotifier {
  PrivacySettingsProvider({
    PrivacySettingsPreference? preference,
    AppAnalytics? analytics,
    AppCrashReporter? crashReporter,
  })  : _preference = preference ?? const PrivacySettingsPreference(),
        _analytics = analytics ?? appAnalytics,
        _crashReporter = crashReporter ?? appCrashReporter;

  final PrivacySettingsPreference _preference;
  final AppAnalytics _analytics;
  final AppCrashReporter _crashReporter;

  bool _loaded = false;
  bool _analyticsEnabled = false;
  bool _crashlyticsEnabled = false;
  bool _consentShown = false;
  Future<void>? _loadFuture;

  bool get loaded => _loaded;

  bool get analyticsEnabled => _analyticsEnabled;

  bool get crashlyticsEnabled => _crashlyticsEnabled;

  bool get consentShown => _consentShown;

  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final analyticsEnabled = await _preference.loadAnalyticsEnabled();
    final crashlyticsEnabled = await _preference.loadCrashlyticsEnabled();
    final consentShown = await _preference.loadConsentShown();
    _analyticsEnabled = analyticsEnabled;
    _crashlyticsEnabled = crashlyticsEnabled;
    _consentShown = consentShown;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAnalyticsEnabled(bool enabled) async {
    await _preference.saveAnalyticsEnabled(enabled);
    _analyticsEnabled = enabled;
    notifyListeners();
    await _analytics.applyPrivacyConsent(enabled);
  }

  Future<void> setCrashlyticsEnabled(bool enabled) async {
    await _preference.saveCrashlyticsEnabled(enabled);
    _crashlyticsEnabled = enabled;
    notifyListeners();
    await _crashReporter.setCollectionEnabled(enabled);
  }

  Future<void> completeConsent({
    required bool analyticsEnabled,
    required bool crashlyticsEnabled,
  }) async {
    await _preference.saveAnalyticsEnabled(analyticsEnabled);
    await _preference.saveCrashlyticsEnabled(crashlyticsEnabled);
    await _preference.saveConsentShown(true);
    _analyticsEnabled = analyticsEnabled;
    _crashlyticsEnabled = crashlyticsEnabled;
    _consentShown = true;
    _loaded = true;
    notifyListeners();
    await _analytics.applyPrivacyConsent(analyticsEnabled);
    await _crashReporter.setCollectionEnabled(crashlyticsEnabled);
  }
}