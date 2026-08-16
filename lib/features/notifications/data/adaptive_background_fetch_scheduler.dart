import 'dart:io';

import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/core/preferences/app_foreground_state_preference.dart';
import 'package:fanotifier/features/notifications/data/background_workmanager_initializer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String fetchBackgroundTask = "fetchBackgroundTask";
const String iOSWorkInitTask = "com.blazesmoker.FANotifier.refresh";
const int backgroundFetchFastIntervalMinutes = 15;
const int backgroundFetchSlowIntervalMinutes = 30;
const int backgroundFetchEmptyStreakThreshold = 4;

enum BackgroundContentFetchOutcome {
  newContent,
  emptySuccess,
  failed,
}

int _normalizedBackgroundFetchIntervalMinutes(int? minutes) {
  return minutes != null && minutes >= backgroundFetchSlowIntervalMinutes
      ? backgroundFetchSlowIntervalMinutes
      : backgroundFetchFastIntervalMinutes;
}

class AdaptiveBackgroundFetchScheduler {
  AdaptiveBackgroundFetchScheduler({
    required this._workmanagerInitializer,
    this._foregroundStatePreference = const AppForegroundStatePreference(),
  });

  static const String _noNotificationStreakKey =
      'backgroundFetchNoNotificationStreak';
  static const String _intervalMinutesKey =
      'backgroundFetchIntervalMinutes';

  final BackgroundWorkmanagerInitializer _workmanagerInitializer;
  final AppForegroundStatePreference _foregroundStatePreference;

  Future<int> loadCurrentBackgroundFetchIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (Platform.isIOS) {
      await prefs.setInt(
        _intervalMinutesKey,
        backgroundFetchFastIntervalMinutes,
      );
      await prefs.setInt(_noNotificationStreakKey, 0);
      return backgroundFetchFastIntervalMinutes;
    }
    return _normalizedBackgroundFetchIntervalMinutes(
      prefs.getInt(_intervalMinutesKey),
    );
  }

  Future<int> recordContentFetchOutcome(
    BackgroundContentFetchOutcome outcome,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (Platform.isIOS) {
      await prefs.setInt(_noNotificationStreakKey, 0);
      await prefs.setInt(
        _intervalMinutesKey,
        backgroundFetchFastIntervalMinutes,
      );
      appLog(
        '[BG] iOS background interval remains fixed at '
        '${backgroundFetchFastIntervalMinutes}m '
        '(outcome: ${outcome.name})',
      );
      return backgroundFetchFastIntervalMinutes;
    }
    if (_foregroundStatePreference.isAppForegroundActive(prefs)) {
      await prefs.setInt(_noNotificationStreakKey, 0);
      await prefs.setInt(
        _intervalMinutesKey,
        backgroundFetchFastIntervalMinutes,
      );
      await _resubmitBackgroundFetchInterval(
        backgroundFetchFastIntervalMinutes,
      );
      return backgroundFetchFastIntervalMinutes;
    }

    final currentStreak = prefs.getInt(_noNotificationStreakKey) ?? 0;
    final int streak;
    final int intervalMinutes;
    switch (outcome) {
      case BackgroundContentFetchOutcome.newContent:
        streak = 0;
        intervalMinutes = backgroundFetchFastIntervalMinutes;
        break;
      case BackgroundContentFetchOutcome.emptySuccess:
        streak = currentStreak >= backgroundFetchEmptyStreakThreshold
            ? backgroundFetchEmptyStreakThreshold
            : currentStreak + 1;
        intervalMinutes = streak >= backgroundFetchEmptyStreakThreshold
            ? backgroundFetchSlowIntervalMinutes
            : backgroundFetchFastIntervalMinutes;
        break;
      case BackgroundContentFetchOutcome.failed:
        streak = currentStreak;
        intervalMinutes = backgroundFetchFastIntervalMinutes;
        break;
    }

    await prefs.setInt(_noNotificationStreakKey, streak);
    await prefs.setInt(_intervalMinutesKey, intervalMinutes);
    await _resubmitBackgroundFetchInterval(
      intervalMinutes,
    );
    appLog(
        '[BG] Adaptive interval set to ${intervalMinutes}m '
        '(empty streak: $streak, outcome: ${outcome.name})');
    return intervalMinutes;
  }

  Future<void> resetAdaptiveBackgroundFetch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await prefs.setInt(_noNotificationStreakKey, 0);
    await prefs.setInt(
      _intervalMinutesKey,
      backgroundFetchFastIntervalMinutes,
    );
    await _resubmitBackgroundFetchInterval(
      backgroundFetchFastIntervalMinutes,
    );
  }

  Future<void> _resubmitBackgroundFetchInterval(int intervalMinutes) async {
    await applyBackgroundFetchInterval(intervalMinutes);
  }

  Future<void> applyBackgroundFetchInterval(int intervalMinutes) async {
    if (Platform.isAndroid) {
      await _workmanagerInitializer.ensureWorkmanagerInitialized();
      await Workmanager().registerPeriodicTask(
        "FANotifier",
        fetchBackgroundTask,
        frequency: Duration(minutes: intervalMinutes),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
      return;
    }
    if (Platform.isIOS) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await prefs.setInt(_noNotificationStreakKey, 0);
      await prefs.setInt(
        _intervalMinutesKey,
        backgroundFetchFastIntervalMinutes,
      );
      appLog(
        '[BG] iOS background interval stored as fixed '
        '${backgroundFetchFastIntervalMinutes}m; native BGTask owns scheduling.',
      );
    }
  }
}
