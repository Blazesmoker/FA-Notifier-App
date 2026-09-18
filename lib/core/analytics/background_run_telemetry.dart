import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/core/crash_reporting/crash_report_privacy.dart';
import 'package:fanotifier/core/preferences/privacy_settings_preference.dart';

class BackgroundRunTelemetry {
  static const keyPrefix = 'background_run_v1_';
  static const retention = Duration(days: 7);
  static const maximumRecords = 100;

  final String id = '${DateTime.now().microsecondsSinceEpoch}_'
      '${Random.secure().nextInt(1 << 32)}';
  final Stopwatch _clock = Stopwatch()..start();
  final Map<String, dynamic> _record = {
    'started_at_ms': DateTime.now().millisecondsSinceEpoch,
    'stage': 'initializing',
    'outcome': 'running',
    'notes_detected': 0,
    'note_submitted': 0,
    'activity_submitted': 0,
    'update_submitted': 0,
    'unread_attempted': 0,
    'unread_restored': 0,
    'errors': <Map<String, String>>[],
    'stages': <String, int>{},
  };
  Future<void> _queue = Future<void>.value();
  bool _enabled = false;
  bool _finished = false;

  Future<void> start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _record['analytics'] =
          prefs.getBool(PrivacySettingsPreference.analyticsEnabledKey) ?? false;
      _record['crashlytics'] =
          prefs.getBool(PrivacySettingsPreference.crashlyticsEnabledKey) ?? false;
      _record['analytics_epoch'] = prefs.getInt(PrivacySettingsPreference.analyticsEpochKey) ?? 0;
      _record['crashlytics_epoch'] = prefs.getInt(PrivacySettingsPreference.crashlyticsEpochKey) ?? 0;
      _enabled = _record['analytics'] == true || _record['crashlytics'] == true;
      if (!_enabled) return;
      _record['run_id'] = id;
      await prune(prefs);
      await _save();
    } catch (_) {}
  }

  void setValue(String key, Object value) {
    if (!_finished) _record[key] = value;
  }

  Future<void> stage(String value) async {
    if (_finished) return;
    _record['stage'] = value;
    (_record['stages'] as Map<String, int>)[value] = _clock.elapsedMilliseconds;
    await _save();
  }

  Future<void> submitted(String type) async {
    if (_finished) return;
    final key = '${type}_submitted';
    _record[key] = (_record[key] as int? ?? 0) + 1;
    await _save();
  }

  Future<void> error(Object error, StackTrace stack) async {
    if (_finished || _record['crashlytics'] != true) return;
    final errors = _record['errors'] as List<Map<String, String>>;
    if (errors.length >= 4) return;
    errors.add({
      'type': CrashReportPrivacy.errorType(error),
      'stack': CrashReportPrivacy.stack(stack).toString(),
      'stage': _record['stage'] as String,
    });
    await _save();
  }

  Future<void> finish(String outcome) async {
    if (_finished) return;
    _record['outcome'] = outcome;
    _record['duration_ms'] = _clock.elapsedMilliseconds;
    _finished = true;
    await _save();
  }

  Future<void> _save() async {
    if (!_enabled) return;
    final snapshot = Map<String, dynamic>.from(_record);
    final encoded = jsonEncode(snapshot);
    _queue = _queue.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final data = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      if (!(prefs.getBool(PrivacySettingsPreference.analyticsEnabledKey) ?? false) ||
          data['analytics_epoch'] != (prefs.getInt(PrivacySettingsPreference.analyticsEpochKey) ?? 0)) {
        data['analytics'] = false;
      }
      if (!(prefs.getBool(PrivacySettingsPreference.crashlyticsEnabledKey) ?? false) ||
          data['crashlytics_epoch'] != (prefs.getInt(PrivacySettingsPreference.crashlyticsEpochKey) ?? 0)) {
        data['crashlytics'] = false;
        data['errors'] = [];
      }
      if (data['analytics'] != true && data['crashlytics'] != true) return;
      await prefs.setString('$keyPrefix$id', jsonEncode(data));
    });
    try {
      await _queue.timeout(const Duration(milliseconds: 300));
    } catch (_) {}
  }

  static Future<void> prune(SharedPreferences prefs) async {
    final keys = prefs.getKeys().where((key) => key.startsWith(keyPrefix)).toList()
      ..sort();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < keys.length; i++) {
      try {
        final data = jsonDecode(prefs.getString(keys[i])!) as Map;
        final age = now - (data['started_at_ms'] as int);
        if (age > retention.inMilliseconds ||
            (i < keys.length - maximumRecords && age > 120000)) {
          await prefs.remove(keys[i]);
        }
      } catch (_) {
        await prefs.remove(keys[i]);
      }
    }
  }

  static Future<void> revoke({required bool analytics}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    for (final key in prefs.getKeys().where((key) => key.startsWith(keyPrefix))) {
      try {
        final data = Map<String, dynamic>.from(jsonDecode(prefs.getString(key)!) as Map);
        data[analytics ? 'analytics' : 'crashlytics'] = false;
        if (!analytics) data['errors'] = [];
        if (data['analytics'] != true && data['crashlytics'] != true) {
          await prefs.remove(key);
        } else {
          await prefs.setString(key, jsonEncode(data));
        }
      } catch (_) {
        await prefs.remove(key);
      }
    }
  }
}
