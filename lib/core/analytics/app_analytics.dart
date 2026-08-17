import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/core/crash_reporting/app_crash_reporter.dart';

enum NotificationExecutionContext {
  backgroundPeriodic('background_periodic'),
  foregroundPeriodic('foreground_periodic'),
  foregroundResume('foreground_resume'),
  foregroundImmediate('foreground_immediate');

  const NotificationExecutionContext(this.analyticsValue);

  final String analyticsValue;
}

enum NotificationCheckOutcome {
  contentFound('content_found'),
  empty('empty'),
  skippedAppActive('skipped_app_active'),
  failed('failed'),
  cancelled('cancelled'),
  timedOut('timed_out');

  const NotificationCheckOutcome(this.analyticsValue);

  final String analyticsValue;
}

class AppAnalytics {
  AppAnalytics({FirebaseAnalytics? analytics})
      : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;
  AppScreen? _currentScreen;
  bool _devicePropertiesConfigured = false;

  Future<void> configureAnonymousDeviceProperties() async {
    if (_devicePropertiesConfigured) return;
    _devicePropertiesConfigured = true;
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        await _setSafeUserProperty('app_device_brand', info.manufacturer);
        await _setSafeUserProperty('app_device_model', info.model);
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        await _setSafeUserProperty('app_device_brand', 'Apple');
        await _setSafeUserProperty('app_device_model', info.utsname.machine);
      }
    } catch (_) {}
  }

  Future<void> logScreen(AppScreen screen) async {
    if (_currentScreen?.name == screen.name &&
        _currentScreen?.screenClass == screen.screenClass) {
      return;
    }
    _currentScreen = screen;
    await appCrashReporter.setScreen(screen.name);
    try {
      await _analytics.logScreenView(
        screenName: screen.name,
        screenClass: screen.screenClass,
      );
    } catch (_) {}
  }

  void resetScreenDeduplication() {
    _currentScreen = null;
  }

  Future<void> logNotificationCheckCompleted({
    required NotificationExecutionContext executionContext,
    required String triggerSource,
    required NotificationCheckOutcome outcome,
    required bool notificationShown,
    required int durationMilliseconds,
  }) {
    return _logEvent(
      'notification_check_completed',
      <String, Object>{
        'execution_context': executionContext.analyticsValue,
        'trigger_source': _safeTriggerSource(triggerSource),
        'outcome': outcome.analyticsValue,
        'notification_shown': notificationShown ? 1 : 0,
        'duration_ms': durationMilliseconds,
      },
    );
  }

  Future<void> logNotificationDisplayed({
    required NotificationExecutionContext executionContext,
    required String notificationType,
  }) {
    return _logEvent(
      'notification_displayed',
      <String, Object>{
        'execution_context': executionContext.analyticsValue,
        'notification_type': _safeNotificationType(notificationType),
      },
    );
  }

  Future<void> logNotificationOpened({
    required String notificationType,
    required NotificationExecutionContext executionContext,
    required String openContext,
  }) {
    return _logEvent(
      'notification_opened',
      <String, Object>{
        'execution_context': executionContext.analyticsValue,
        'notification_type': _safeNotificationType(notificationType),
        'open_context': _safeOpenContext(openContext),
      },
    );
  }

  NotificationExecutionContext foregroundContext(String source) {
    if (source == 'timer') {
      return NotificationExecutionContext.foregroundPeriodic;
    }
    if (source == 'lifecycle_resumed') {
      return NotificationExecutionContext.foregroundResume;
    }
    return NotificationExecutionContext.foregroundImmediate;
  }

  Future<void> _setSafeUserProperty(String name, String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return;
    final safeValue = normalized.length <= 36
        ? normalized
        : normalized.substring(0, 36);
    await _analytics.setUserProperty(name: name, value: safeValue);
  }

  Future<void> _logEvent(
    String name,
    Map<String, Object> parameters,
  ) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (_) {}
  }

  String _safeTriggerSource(String source) {
    const known = <String>{
      'workmanager',
      'timer',
      'lifecycle_resumed',
      'startup_warmup',
      'login_established',
      'notifications_first_open',
      'notifications_empty_autorefresh',
      'notification_refresh_service',
      'notes_entry_baseline',
      'external_counts',
      'foreground_entry_visible',
      'acknowledging_screen_visible',
      'pending_start',
      'notifications_empty_refresh_indicator',
      'notifications_refresh_indicator',
      'notes_screen_two_page_refresh',
      'notes_screen_inbox_refresh',
    };
    return known.contains(source) ? source : 'other_internal';
  }

  String _safeNotificationType(String type) {
    return const <String>{'note', 'activity', 'update'}.contains(type)
        ? type
        : 'unknown';
  }

  String _safeOpenContext(String context) {
    if (context.startsWith('tap:')) return 'direct_tap';
    if (context == 'after_first_frame_boot') return 'cold_start';
    if (context == 'app_lifecycle_resumed') return 'resume';
    return 'other';
  }
}

final AppAnalytics appAnalytics = AppAnalytics();

class AppAnalyticsRouteObserver extends NavigatorObserver {
  void _report(Route<dynamic>? route) {
    final settings = route?.settings;
    if (settings is AnalyticsRouteSettings) {
      appAnalytics.logScreen(settings.screen);
    } else {
      appAnalytics.resetScreenDeduplication();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _report(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _report(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _report(newRoute);
  }
}
