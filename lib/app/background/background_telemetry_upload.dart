import 'dart:async';
import 'dart:convert';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/core/preferences/privacy_settings_preference.dart';
import 'package:fanotifier/core/analytics/background_run_telemetry.dart';

class BackgroundTelemetryUpload {
  static Future<void>? _inFlight;

  static Future<void> flush() {
    return _inFlight ??= _flush().catchError((_) {}).whenComplete(() {
      _inFlight = null;
    });
  }

  static bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  static Future<void> _flush() async {
    if (!_foreground || Firebase.apps.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await BackgroundRunTelemetry.prune(prefs);
    final keys = prefs.getKeys()
        .where((key) => key.startsWith(BackgroundRunTelemetry.keyPrefix))
        .toList()..sort();
    for (final key in keys) {
      if (!_foreground) return;
      await prefs.reload();
      final encoded = prefs.getString(key);
      if (encoded == null) continue;
      final record = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
      final age = DateTime.now().millisecondsSinceEpoch -
          (record['started_at_ms'] as int);
      if (record['outcome'] == 'running' && age < 120000) continue;
      record['analytics'] = record['analytics'] == true &&
          record['analytics_epoch'] == (prefs.getInt(PrivacySettingsPreference.analyticsEpochKey) ?? 0);
      record['crashlytics'] = record['crashlytics'] == true &&
          record['crashlytics_epoch'] == (prefs.getInt(PrivacySettingsPreference.crashlyticsEpochKey) ?? 0);
      final parameters = <String, Object>{
        'execution_context': 'background_periodic',
        'trigger_source': 'workmanager',
        'run_id': record['run_id'] as String,
        'occurred_at_ms': record['started_at_ms'] as int,
        'deferred_upload': 1,
        'outcome': record['outcome'] == 'running' ? 'interrupted' : record['outcome'] as String,
        'source_app_version': record['source_app_version'] as String? ?? 'unknown',
        for (final stage in ['github_preflight', 'inbox', 'note_content', 'unread_restore', 'note_delivery', 'activity'])
          if ((record['stages'] as Map)[stage] is int)
            '${stage}_at_ms': (record['stages'] as Map)[stage] as int,
        'last_stage': record['stage'] as String,
        'launch_context': record['launch_context'] as String? ?? 'unknown',
        'notification_shown': (record['note_submitted'] as int) +
            (record['activity_submitted'] as int) +
            (record['update_submitted'] as int) > 0 ? 1 : 0,
        for (final field in ['duration_ms', 'notes_detected', 'note_submitted',
          'activity_submitted', 'unread_attempted', 'unread_restored', 'unread_status'])
          if (record[field] is int) field: record[field] as int,
      };
      final events = <(String, Map<String, Object>)>[
        ('notification_check_completed', parameters),
        for (final type in ['note', 'activity', 'update'])
          for (var i = 0; i < (record['${type}_submitted'] as int); i++)
            ('notification_displayed', {
              'execution_context': 'background_periodic',
              'notification_type': type,
              'run_id': record['run_id'] as String,
              'occurred_at_ms': record['started_at_ms'] as int,
              'deferred_upload': 1,
              'submission_index': i,
            }),
      ];
      var cursor = record['upload_cursor'] as int? ?? 0;
      if (record['analytics'] == true &&
          (prefs.getBool(PrivacySettingsPreference.analyticsEnabledKey) ?? false)) {
        while (cursor < events.length) {
          if (!_foreground) return;
          await prefs.reload();
          if (!_foreground) return;
          if (!(prefs.getBool(PrivacySettingsPreference.analyticsEnabledKey) ?? false) ||
              record['analytics_epoch'] != (prefs.getInt(PrivacySettingsPreference.analyticsEpochKey) ?? 0)) {
            break;
          }
          final event = events[cursor];
          await FirebaseAnalytics.instance.logEvent(name: event.$1, parameters: event.$2)
              .timeout(const Duration(seconds: 2));
          record['upload_cursor'] = ++cursor;
          if (!await _saveProgress(prefs, key, record)) return;
        }
      }
      final errors = record['errors'] as List;
      var errorCursor = record['error_cursor'] as int? ?? 0;
      while (record['crashlytics'] == true && errorCursor < errors.length) {
        if (!_foreground) return;
        await prefs.reload();
        if (!_foreground) return;
        if (!(prefs.getBool(PrivacySettingsPreference.crashlyticsEnabledKey) ?? false) ||
            record['crashlytics_epoch'] != (prefs.getInt(PrivacySettingsPreference.crashlyticsEpochKey) ?? 0)) {
          break;
        }
        final error = errors[errorCursor] as Map;
        await FirebaseCrashlytics.instance.recordError(
          error['type'] as String,
          StackTrace.fromString(error['stack'] as String),
          reason: 'deferred_background_fetch_error',
          information: [
            'run_id=${record['run_id']}',
            'occurred_at_ms=${record['started_at_ms']}',
            'stage=${error['stage']}',
            'execution_context=background_periodic',
          ],
          printDetails: false,
          fatal: false,
        ).timeout(const Duration(seconds: 2));
        record['error_cursor'] = ++errorCursor;
        if (!await _saveProgress(prefs, key, record)) return;
      }
      await prefs.remove(key);
    }
  }
  static Future<bool> _saveProgress(
    SharedPreferences prefs,
    String key,
    Map<String, dynamic> record,
  ) async {
    await prefs.reload();
    final current = prefs.getString(key);
    if (current == null) return false;
    final data = Map<String, dynamic>.from(jsonDecode(current) as Map);
    data['upload_cursor'] = record['upload_cursor'] ?? 0;
    data['error_cursor'] = record['error_cursor'] ?? 0;
    return prefs.setString(key, jsonEncode(data));
  }

}
