import 'dart:io';

import 'package:FANotifier/core/logging/app_logging.dart';
import 'package:FANotifier/features/notifications/data/notification_service.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _currentActivityNotificationIdKey =
    'currentActivityNotificationId';
const String _currentActivityNotificationBadgeCountedKey =
    'currentActivityNotificationBadgeCounted';
const String _iosNoteBadgeCountKey = 'iosNoteBadgeCount';

Future<int?> nextIOSNoteBadgeNumberForNotification() async {
  if (!Platform.isIOS) return null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final noteCount = (prefs.getInt(_iosNoteBadgeCountKey) ?? 0) + 1;
  final activityCounted =
      prefs.getBool(_currentActivityNotificationBadgeCountedKey) ?? false;
  final badgeNumber = noteCount + (activityCounted ? 1 : 0);
  appLog(
    '[BADGE] producer=background_note notes=$noteCount '
    'activitySlot=$activityCounted desired=$badgeNumber',
  );
  return badgeNumber;
}

Future<void> commitIOSNoteBadgeNumber(int? badgeNumber) async {
  if (badgeNumber == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final noteCount = (prefs.getInt(_iosNoteBadgeCountKey) ?? 0) + 1;
  await prefs.setInt(_iosNoteBadgeCountKey, noteCount);
  await prefs.setInt('badgeCounter', badgeNumber);
  appLog(
    '[BADGE] producer=background_note committed notes=$noteCount '
    'badge=$badgeNumber',
  );
}

Future<int?> nextIOSActivityBadgeNumberForNotification() async {
  if (!Platform.isIOS) return null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final noteCount = prefs.getInt(_iosNoteBadgeCountKey) ?? 0;
  final badgeNumber = noteCount + 1;
  appLog(
    '[BADGE] producer=background_activity notes=$noteCount '
    'activitySlot=true desired=$badgeNumber',
  );
  return badgeNumber;
}

Future<void> commitIOSActivityBadgeNumber(int? badgeNumber) async {
  if (badgeNumber == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  await prefs.setBool(_currentActivityNotificationBadgeCountedKey, true);
  await prefs.setInt('badgeCounter', badgeNumber);
  appLog(
    '[BADGE] producer=background_activity committed activitySlot=true '
    'badge=$badgeNumber',
  );
}

Future<void> removePreviousActivityNotification(
  NotificationService notificationService, {
  int? replacingWithId,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final previousActivityNotificationId =
      prefs.getInt(_currentActivityNotificationIdKey);
  if (Platform.isIOS) {
    final idsToCancel = <int>{
      if (previousActivityNotificationId != null) previousActivityNotificationId,
      if (replacingWithId != null) replacingWithId,
    };
    for (final id in idsToCancel) {
      await notificationService.cancelNotification(id);
    }
    return;
  }
  if (previousActivityNotificationId != null) {
    await notificationService.cancelNotification(previousActivityNotificationId);
  }
  await prefs.remove(_currentActivityNotificationIdKey);
  await prefs.remove(_currentActivityNotificationBadgeCountedKey);
}

Future<void> rememberActivityNotification(
  int activityNotificationId,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(
    _currentActivityNotificationIdKey,
    activityNotificationId,
  );
  if (!Platform.isIOS) {
    await prefs.setBool(_currentActivityNotificationBadgeCountedKey, false);
  }
}

Future<int?> syncIOSBadgeFromState({SharedPreferences? prefs}) async {
  if (!Platform.isIOS) return null;
  final badgePrefs = prefs ?? await SharedPreferences.getInstance();
  if (prefs == null) {
    await badgePrefs.reload();
  }
  final noteCount = badgePrefs.getInt(_iosNoteBadgeCountKey) ?? 0;
  final activityCounted =
      badgePrefs.getBool(_currentActivityNotificationBadgeCountedKey) ?? false;
  final badgeNumber = noteCount + (activityCounted ? 1 : 0);
  await badgePrefs.setInt('badgeCounter', badgeNumber);
  try {
    await AppBadgePlus.updateBadge(badgeNumber);
  } catch (e) {
    appLog('[BADGE] Failed to update iOS app badge: $e');
  }
  return badgeNumber;
}

Future<void> resetBadgeCounter() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('badgeCounter', 0);
  await prefs.remove(_iosNoteBadgeCountKey);
  if (prefs.getInt(_currentActivityNotificationIdKey) == null) {
    await prefs.remove(_currentActivityNotificationBadgeCountedKey);
  } else {
    await prefs.setBool(_currentActivityNotificationBadgeCountedKey, false);
  }
  if (Platform.isIOS) {
    await syncIOSBadgeFromState(prefs: prefs);
  }
}
