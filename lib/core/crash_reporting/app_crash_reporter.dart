import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class AppCrashReporter {
  AppCrashReporter({FirebaseCrashlytics? crashlytics})
      : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;

  Future<void> initializeMainIsolate({
    required bool collectionEnabled,
  }) async {
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(collectionEnabled);
      await _crashlytics.setUserIdentifier('');
    } catch (_) {}
    FlutterError.onError = (details) {
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
      unawaited(
        _recordFlutterError(
          details,
          executionContext: 'foreground_flutter',
          origin: 'flutter_framework',
        ),
      );
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(
        _recordUncaughtError(
          error,
          stackTrace,
          executionContext: 'foreground_platform',
          origin: 'platform_dispatcher',
        ),
      );
      return true;
    };
  }

  Future<void> initializeBackgroundIsolate({
    required bool collectionEnabled,
  }) async {
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(collectionEnabled);
      await _crashlytics.setUserIdentifier('');
    } catch (_) {}
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(
        _recordUncaughtError(
          error,
          stackTrace,
          executionContext: 'background_periodic',
          origin: 'background_dispatcher',
        ),
      );
      return true;
    };
  }

  Future<void> _recordFlutterError(
    FlutterErrorDetails details, {
    required String executionContext,
    required String origin,
  }) async {
    final fatal = _isFatal(details.exception, silent: details.silent);
    try {
      await _setReportMetadata(
        error: details.exception,
        executionContext: executionContext,
        origin: origin,
        fatal: fatal,
      );
      final information = details.informationCollector?.call() ?? const [];
      await _crashlytics.recordError(
        details.exception,
        details.stack,
        reason: details.context
            ?.toStringDeep(minLevel: DiagnosticLevel.info)
            .trim(),
        information: information,
        printDetails: false,
        fatal: fatal,
      );
    } catch (_) {}
  }

  Future<void> _recordUncaughtError(
    Object error,
    StackTrace stackTrace, {
    required String executionContext,
    required String origin,
  }) async {
    final fatal = _isFatal(error);
    try {
      await _setReportMetadata(
        error: error,
        executionContext: executionContext,
        origin: origin,
        fatal: fatal,
      );
      await _crashlytics.recordError(
        error,
        stackTrace,
        fatal: fatal,
      );
    } catch (_) {}
  }

  Future<void> recordNonFatal(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    required String executionContext,
  }) async {
    try {
      await _setReportMetadata(
        error: error,
        executionContext: executionContext,
        origin: 'manual_report',
        fatal: false,
      );
      await _crashlytics.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: false,
      );
    } catch (_) {}
  }

  bool _isFatal(Object error, {bool silent = false}) {
    return !silent && error is Error;
  }

  Future<void> _setReportMetadata({
    required Object error,
    required String executionContext,
    required String origin,
    required bool fatal,
  }) async {
    await _crashlytics.setCustomKey('execution_context', executionContext);
    await _crashlytics.setCustomKey(
      'error_type',
      error.runtimeType.toString(),
    );
    await _crashlytics.setCustomKey('error_origin', origin);
    await _crashlytics.setCustomKey(
      'reported_severity',
      fatal ? 'fatal' : 'non_fatal',
    );
  }

  Future<void> setCollectionEnabled(bool enabled) async {
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
    } catch (_) {}
  }

  Future<void> setScreen(String screenName) async {
    try {
      await _crashlytics.setCustomKey('current_screen', screenName);
    } catch (_) {}
  }
}

final AppCrashReporter appCrashReporter = AppCrashReporter();
