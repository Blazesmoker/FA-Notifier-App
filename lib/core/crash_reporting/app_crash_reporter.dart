import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class AppCrashReporter {
  AppCrashReporter({FirebaseCrashlytics? crashlytics})
      : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  final FirebaseCrashlytics _crashlytics;

  Future<void> initializeMainIsolate() async {
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
      await _crashlytics.setUserIdentifier('');
    } catch (_) {}
    FlutterError.onError = (details) {
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
      recordFatal(
        details.exception,
        details.stack ?? StackTrace.current,
        executionContext: 'foreground_flutter',
      );
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      recordFatal(
        error,
        stackTrace,
        executionContext: 'foreground_platform',
      );
      return true;
    };
  }

  Future<void> initializeBackgroundIsolate() async {
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
      await _crashlytics.setUserIdentifier('');
    } catch (_) {}
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      recordFatal(
        error,
        stackTrace,
        executionContext: 'background_periodic',
      );
      return true;
    };
  }

  Future<void> recordFatal(
    Object error,
    StackTrace stackTrace, {
    required String executionContext,
  }) async {
    try {
      await _crashlytics.setCustomKey('execution_context', executionContext);
      await _crashlytics.setCustomKey(
        'error_type',
        error.runtimeType.toString(),
      );
      await _crashlytics.recordError(
        _AnonymousCrashError(error.runtimeType.toString()),
        stackTrace,
        fatal: true,
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
      await _crashlytics.setCustomKey('execution_context', executionContext);
      await _crashlytics.setCustomKey(
        'error_type',
        error.runtimeType.toString(),
      );
      await _crashlytics.recordError(
        _AnonymousCrashError(error.runtimeType.toString()),
        stackTrace,
        reason: reason,
        fatal: false,
      );
    } catch (_) {}
  }

  Future<void> setScreen(String screenName) async {
    try {
      await _crashlytics.setCustomKey('current_screen', screenName);
    } catch (_) {}
  }
}

final AppCrashReporter appCrashReporter = AppCrashReporter();

class _AnonymousCrashError {
  const _AnonymousCrashError(this.type);

  final String type;

  @override
  String toString() => type;
}
