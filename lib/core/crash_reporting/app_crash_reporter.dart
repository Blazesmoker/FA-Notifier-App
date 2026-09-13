import 'dart:async';
import 'dart:collection';
import 'dart:ui' show AppLifecycleState;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../preferences/privacy_settings_preference.dart';
import 'crash_report_privacy.dart';

enum CrashBreadcrumb {
  incomingLink,
  navigationReady,
  navigationNotReady,
  backgroundWorkerStarted,
}

class AppCrashReporter {
  AppCrashReporter({FirebaseCrashlytics? crashlytics})
      : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;
  final Stopwatch _uptime = Stopwatch()..start();
  final LinkedHashMap<String, int> _recentReports = LinkedHashMap();
  final List<String> _breadcrumbs = [];
  Future<void> _queue = Future<void>.value();
  bool _collectionEnabled = false;
  bool _background = false;
  int _consentGeneration = 0;
  int _pendingReports = 0;
  int _windowStarted = 0;
  int _windowReports = 0;
  int _windowAttempts = 0;
  int _suppressedReports = 0;
  String _screen = 'unknown';
  String _lifecycle = 'unknown';

  Future<void> initializeMainIsolate({
    required bool collectionEnabled,
  }) async {
    _background = false;
    await setCollectionEnabled(collectionEnabled);
    FlutterError.onError = (details) {
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
      unawaited(_record(
        details.exception,
        details.stack,
        executionContext: 'foreground_flutter',
        origin: 'flutter_framework',
        category: 'framework_error',
        silent: details.silent,
        library: details.library,
      ));
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(_record(
        error,
        stackTrace,
        executionContext: 'foreground_platform',
        origin: 'platform_dispatcher',
        category: 'uncaught_async_error',
      ));
      return true;
    };
  }

  Future<void> initializeBackgroundIsolate({
    required bool collectionEnabled,
  }) async {
    _background = true;
    await setCollectionEnabled(collectionEnabled);
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(_record(
        error,
        stackTrace,
        executionContext: 'background_periodic',
        origin: 'background_dispatcher',
        category: 'uncaught_async_error',
      ));
      return true;
    };
  }

  Future<void> recordNonFatal(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    required String executionContext,
  }) {
    return _record(
      error,
      stackTrace,
      executionContext: executionContext,
      origin: 'manual_report',
      category: 'caught_exception',
      reason: reason,
    );
  }

  Future<void> _record(
    Object error,
    StackTrace? stackTrace, {
    required String executionContext,
    required String origin,
    required String category,
    String? reason,
    String? library,
    bool silent = false,
  }) {
    if (!_collectionEnabled) return Future<void>.value();
    final now = _uptime.elapsedMilliseconds;
    if (now - _windowStarted >= 30000) {
      _windowStarted = now;
      _windowReports = 0;
      _windowAttempts = 0;
    }
    if (_pendingReports >= 8 ||
        _windowReports >= 8 ||
        _windowAttempts >= 32) {
      _countSuppressed();
      return Future<void>.value();
    }
    _windowAttempts++;
    try {
      final safeError = CrashReportPrivacy.errorSummary(error);
      final safeStack = CrashReportPrivacy.stack(stackTrace);
      final safeContext = CrashReportPrivacy.executionContext(executionContext);
      final fingerprint = '$origin|$safeContext|$safeError|'
          '${safeStack.toString().split('\n').take(8).join('\n')}';
      final lastReported = _recentReports[fingerprint];
      if (lastReported != null && now - lastReported < 30000) {
        _countSuppressed();
        return Future<void>.value();
      }
      _recentReports.remove(fingerprint);
      if (_recentReports.length >= 32) {
        _recentReports.remove(_recentReports.keys.first);
      }
      _recentReports[fingerprint] = now;
      final metadata = Map<String, Object>.unmodifiable({
        'reporting_policy_version': 2,
        'execution_context': safeContext,
        'error_type': CrashReportPrivacy.errorType(error),
        'error_origin': origin,
        'error_category': category,
        'reported_severity': 'non_fatal',
        'process_termination': 'not_determined',
        'current_screen': _background ? 'background_worker' : _screen,
        'lifecycle_state': _background ? 'headless' : _lifecycle,
        'isolate_uptime_ms': now,
        'build_mode':
            kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
        'flutter_library': CrashReportPrivacy.library(library),
        'flutter_silent': silent,
        'sampling': 'bounded_per_isolate',
        'suppressed_since_previous_report': _suppressedReports,
      });
      final information = List<Object>.unmodifiable([
        ...metadata.entries.map((entry) => '${entry.key}=${entry.value}'),
        ..._breadcrumbs.map((entry) => 'breadcrumb=$entry'),
      ]);
      final reportReason = '${CrashReportPrivacy.reason(reason)}; '
          'category=$category; context=$safeContext; '
          'screen=${metadata['current_screen']}; '
          'lifecycle=${metadata['lifecycle_state']}; '
          'library=${metadata['flutter_library']}';
      final generation = _consentGeneration;
      _suppressedReports = 0;
      _windowReports++;
      _pendingReports++;
      final submission = _queue.then((_) async {
        try {
          if (!_canSubmit(generation)) return;
          if (!await _hasPersistedConsent()) return;
          for (final entry in metadata.entries) {
            if (!_canSubmit(generation)) return;
            try {
              await _crashlytics.setCustomKey(entry.key, entry.value);
            } catch (_) {}
          }
          if (!_canSubmit(generation)) return;
          await _crashlytics.recordError(
            safeError,
            safeStack,
            reason: reportReason,
            information: information,
            printDetails: false,
            fatal: false,
          );
        } catch (_) {
          if (_canSubmit(generation)) _countSuppressed();
        } finally {
          _pendingReports--;
        }
      });
      _queue = submission;
      return submission;
    } catch (_) {
      return Future<void>.value();
    }
  }

  Future<bool> _hasPersistedConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getBool(PrivacySettingsPreference.crashlyticsEnabledKey) ??
          false;
    } catch (_) {
      return false;
    }
  }

  bool _canSubmit(int generation) {
    return _collectionEnabled && generation == _consentGeneration;
  }

  void _countSuppressed() {
    if (_suppressedReports < 1000000) _suppressedReports++;
  }

  void _addBreadcrumb(String value) {
    if (!_collectionEnabled) return;
    if (_breadcrumbs.length == 20) _breadcrumbs.removeAt(0);
    _breadcrumbs.add('${_uptime.elapsedMilliseconds}ms $value');
  }

  void addBreadcrumb(CrashBreadcrumb event) {
    _addBreadcrumb(event.name);
  }

  void setLifecycle(AppLifecycleState state) {
    _lifecycle = state.name;
    _addBreadcrumb('lifecycle=${state.name}');
  }

  void recordNavigation(String category) {
    const known = {
      'gallery',
      'galleryFolder',
      'scraps',
      'user',
      'journalUser',
      'journal',
      'submission',
      'external',
    };
    final safeCategory = known.contains(category) ? category : 'unknown';
    _addBreadcrumb('navigation=$safeCategory');
  }

  void recordNotificationCheck(String outcome) {
    const known = {
      'content_found',
      'empty',
      'skipped_app_active',
      'failed',
      'cancelled',
      'timed_out',
    };
    final safeOutcome = known.contains(outcome) ? outcome : 'unknown';
    _addBreadcrumb('notification_check=$safeOutcome');
  }

  Future<void> setCollectionEnabled(bool enabled) async {
    if (_collectionEnabled != enabled) {
      _consentGeneration++;
      _recentReports.clear();
      _breadcrumbs.clear();
      _suppressedReports = 0;
      _windowStarted = _uptime.elapsedMilliseconds;
      _windowReports = 0;
      _windowAttempts = 0;
    }
    _collectionEnabled = enabled;
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
    } catch (_) {}
    try {
      await _crashlytics.setUserIdentifier('');
    } catch (_) {}
  }

  Future<void> setScreen(String screenName) async {
    _screen = CrashReportPrivacy.screen(screenName);
    _addBreadcrumb('screen=$_screen');
  }
}

final AppCrashReporter appCrashReporter = AppCrashReporter();
