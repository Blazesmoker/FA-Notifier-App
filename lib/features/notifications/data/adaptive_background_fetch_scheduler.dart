import 'dart:io';

import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/core/preferences/app_foreground_state_preference.dart';
import 'package:fanotifier/features/notifications/data/background_workmanager_initializer.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String fetchBackgroundTask = "fetchBackgroundTask";
const String iOSWorkInitTask = "com.blazesmoker.FANotifier.refresh";
const int backgroundFetchFastIntervalMinutes = 2;
const int backgroundFetchSlowIntervalMinutes = 30;

int _normalizedBackgroundFetchIntervalMinutes(int? minutes) {
  return minutes != null && minutes >= backgroundFetchSlowIntervalMinutes
      ? backgroundFetchSlowIntervalMinutes
      : backgroundFetchFastIntervalMinutes;
}

class AdaptiveBackgroundFetchScheduler {
  AdaptiveBackgroundFetchScheduler({
    required BackgroundWorkmanagerInitializer workmanagerInitializer,
    AppForegroundStatePreference foregroundStatePreference =
        const AppForegroundStatePreference(),
    MethodChannel backgroundFetchChannel =
        const MethodChannel('app.background_fetch'),
  })  : _workmanagerInitializer = workmanagerInitializer,
        _foregroundStatePreference = foregroundStatePreference,
        _backgroundFetchChannel = backgroundFetchChannel;

  static const String _noNotificationStreakKey =
      'backgroundFetchNoNotificationStreak';
  static const String _intervalMinutesKey =
      'backgroundFetchIntervalMinutes';

  final BackgroundWorkmanagerInitializer _workmanagerInitializer;
  final AppForegroundStatePreference _foregroundStatePreference;
  final MethodChannel _backgroundFetchChannel;

  Future<int> loadCurrentBackgroundFetchIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _normalizedBackgroundFetchIntervalMinutes(
      prefs.getInt(_intervalMinutesKey),
    );
  }

  Future<void> updateAdaptiveBackgroundFetchAfterTask({
    required bool didShowNotification,
    required bool completedNoNewContentCheck,
  }) async {
    if (!didShowNotification && !completedNoNewContentCheck) {
      await resetAdaptiveBackgroundFetch();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final previousIntervalMinutes = _normalizedBackgroundFetchIntervalMinutes(
      prefs.getInt(_intervalMinutesKey),
    );
    if (_foregroundStatePreference.isAppForegroundActive(prefs)) {
      await prefs.setInt(_noNotificationStreakKey, 0);
      await prefs.setInt(
        _intervalMinutesKey,
        backgroundFetchFastIntervalMinutes,
      );
      await _resubmitBackgroundFetchInterval(
        backgroundFetchFastIntervalMinutes,
        previousIntervalMinutes: previousIntervalMinutes,
      );
      return;
    }

    final int streak;
    if (didShowNotification) {
      streak = 0;
    } else {
      final current = prefs.getInt(_noNotificationStreakKey) ?? 0;
      streak = current >= 4 ? 4 : current + 1;
    }

    final intervalMinutes = streak >= 4
        ? backgroundFetchSlowIntervalMinutes
        : backgroundFetchFastIntervalMinutes;
    await prefs.setInt(_noNotificationStreakKey, streak);
    await prefs.setInt(_intervalMinutesKey, intervalMinutes);
    await _resubmitBackgroundFetchInterval(
      intervalMinutes,
      previousIntervalMinutes: previousIntervalMinutes,
    );
    appLog(
        '[BG] Adaptive interval set to ${intervalMinutes}m '
        '(empty streak: $streak, notification shown: $didShowNotification)');
  }

  Future<void> resetAdaptiveBackgroundFetch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final previousIntervalMinutes = _normalizedBackgroundFetchIntervalMinutes(
      prefs.getInt(_intervalMinutesKey),
    );
    await prefs.setInt(_noNotificationStreakKey, 0);
    await prefs.setInt(
      _intervalMinutesKey,
      backgroundFetchFastIntervalMinutes,
    );
    await _resubmitBackgroundFetchInterval(
      backgroundFetchFastIntervalMinutes,
      previousIntervalMinutes: previousIntervalMinutes,
    );
  }

  Future<void> _resubmitBackgroundFetchInterval(
    int intervalMinutes, {
    required int previousIntervalMinutes,
  }) async {
    await applyBackgroundFetchInterval(
      intervalMinutes,
      previousIntervalMinutes: previousIntervalMinutes,
    );
  }

  Future<void> applyBackgroundFetchInterval(
    int intervalMinutes, {
    int? previousIntervalMinutes,
  }) async {
    if (Platform.isAndroid) {
      await _workmanagerInitializer.ensureWorkmanagerInitialized();
      await Workmanager().registerPeriodicTask(
        "FANotify",
        fetchBackgroundTask,
        frequency: Duration(minutes: intervalMinutes),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
      return;
    }
    if (Platform.isIOS) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final nextApprox =
            DateTime.now().add(Duration(minutes: intervalMinutes));
        if (_foregroundStatePreference.isAppForegroundActive(prefs)) {
          appLog(
            '[BG] iOS foreground active; stored ${intervalMinutes}m interval. '
            'Native active lifecycle scheduling remains in effect.',
          );
          return;
        }
        appLog(
          '[BG] Requesting iOS background fetch reschedule: '
          '${intervalMinutes}m, next approx >= $nextApprox',
        );
        await _backgroundFetchChannel.invokeMethod<void>(
          'reschedule',
          <String, int>{
            'minutes': intervalMinutes,
            if (previousIntervalMinutes != null)
              'previousMinutes': previousIntervalMinutes,
          },
        );
        appLog(
          '[BG] iOS background fetch reschedule request sent: '
          '${intervalMinutes}m, next approx >= $nextApprox',
        );
      } catch (e) {
        appLog('[BG] Failed to reschedule iOS background fetch: $e');
      }
    }
  }
}
