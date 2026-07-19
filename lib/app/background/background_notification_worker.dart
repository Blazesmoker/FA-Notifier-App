import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:FANotifier/core/logging/app_logging.dart';
import 'package:FANotifier/core/network/fresh_http_overrides.dart';
import 'package:FANotifier/core/preferences/app_foreground_state_preference.dart';
import 'package:FANotifier/features/drawer/data/app_update_service.dart';
import 'package:FANotifier/features/notes/data/background_inbox_service.dart';
import 'package:FANotifier/features/notes/data/background_note_content_service.dart';
import 'package:FANotifier/features/notes/data/background_note_unread_service.dart';
import 'package:FANotifier/features/notes/data/message_storage.dart';
import 'package:FANotifier/features/notes/domain/background_inbox_models.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/features/notifications/data/activities_notification_state.dart';
import 'package:FANotifier/features/notifications/data/adaptive_background_fetch_scheduler.dart'
    as background_scheduler;
import 'package:FANotifier/features/notifications/data/notification_badge_state.dart'
    as notification_badge;
import 'package:FANotifier/features/notifications/data/notification_service.dart';
import 'package:FANotifier/features/notifications/domain/activity_count_change_policy.dart';
import 'package:FANotifier/shared/fa/domain/notification_counts.dart';
import 'package:FANotifier/features/notifications/domain/notification_message_formatter.dart';
import 'package:FANotifier/features/notifications/domain/stable_notification_id.dart';
import 'package:FANotifier/core/network/fa_http.dart';

class BackgroundNotificationWorker {
  static const ActivityCountChangePolicy _countChangePolicy =
      ActivityCountChangePolicy();

  BackgroundNotificationWorker({
    required background_scheduler.AdaptiveBackgroundFetchScheduler
        adaptiveBackgroundFetchScheduler,
    AppForegroundStatePreference appForegroundStatePreference =
        const AppForegroundStatePreference(),
  })  : _adaptiveBackgroundFetchScheduler = adaptiveBackgroundFetchScheduler,
        _appForegroundStatePreference = appForegroundStatePreference;

  final background_scheduler.AdaptiveBackgroundFetchScheduler
      _adaptiveBackgroundFetchScheduler;
  final AppForegroundStatePreference _appForegroundStatePreference;

  Future<bool> execute(
    String task,
    Map<String, dynamic>? inputData,
  ) async {
    appLog("===============================================");
    appLog("BACKGROUND TASK TRIGGERED: $task");
    appLog("Time: ${DateTime.now()}");
    appLog("===============================================");
    final startTime = DateTime.now();
    bool didShowBackgroundNotification = false;
    bool didFindNewNotificationContent = false;
    bool didCompleteNotesCheck = false;
    bool didCompleteActivitiesCheck = false;
    try {
      final notificationService = NotificationService();
      await notificationService.init();
      appLog("[BG] NotificationService initialized");
      SharedPreferences prefs;
      try {
        prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        appLog('[BG] SharedPreferences loaded successfully');
        await FAHttp.initFromPrefs(prefs: prefs);
        HttpOverrides.global = FreshHttpOverrides();
      } catch (e) {
        appLog('[BG ERROR] Failed to load SharedPreferences: $e');
        return Future.value(false);
      }
      final bool isAppActive =
          _appForegroundStatePreference.isAppForegroundActive(prefs);
      appLog('[BG] App active status: $isAppActive');
      if (isAppActive) {
        appLog('[BG] App is ACTIVE - skipping background fetch');
        appLog(
            '[BG] Task completed (skipped) in ${DateTime.now().difference(startTime).inSeconds}s');
        return Future.value(true);
      }
      appLog('[BG] App is INACTIVE - proceeding with background fetch');
      if (task == background_scheduler.fetchBackgroundTask ||
          task == background_scheduler.iOSWorkInitTask ||
          task == Workmanager.iOSBackgroundTask) {
        appLog('[BG] Valid background task detected: $task');
        kDebugPrint('[BG] Headless background worker is running.');
        try {
          final currentVersionAllowed = await isCurrentAppVersionAllowed();
          if (currentVersionAllowed == false) {
            appLog('[BG] Current app version is not allowed - skipping fetch');
            await _showBackgroundUpdateNotificationIfNeeded(
              notificationService,
              prefs,
            );
            return Future.value(true);
          }
          bool didFirstRunSkip = prefs.getBool('did_first_run_skip') ?? false;
          appLog('[BG] First run skip status: $didFirstRunSkip');
          if (!didFirstRunSkip) {
            appLog('[BG] First run not complete - skipping notifications');
            return Future.value(true);
          }
          NotificationCounts? currentCounts;

          appLog('[BG] === Starting UNREAD NOTES CHECK ===');
          try {
            final Set<String> shownSet = await MessageStorage.getShownNoteIds();
            final Set<String> seenSet = await MessageStorage.getSeenNoteIds();
            final BackgroundInboxSnapshot snapshot =
                await fetchBackgroundInboxSnapshot(
              shownNoteIds: shownSet,
              seenNoteIds: seenSet,
            );
            final List<Message> fetchedInbox = snapshot.messages;
            currentCounts = snapshot.topbarCounts;
            await prefs.reload();
            if (_appForegroundStatePreference.isAppForegroundActive(prefs)) {
              return Future.value(true);
            }
            kDebugPrint(
              '[BG] Fetched ${fetchedInbox.length} messages from inbox '
              '(page2=${snapshot.fetchedPage2})',
            );
            kDebugPrint(
                '[BG] Already shown: ${shownSet.length} message IDs; seen: ${seenSet.length}');
            if (currentCounts != null) {
              final countsForLog = currentCounts;
              kDebugPrint(
                  '[BG] Page 1 topbar counts: S:${countsForLog.submissions} W:${countsForLog.watches} C:${countsForLog.comments} F:${countsForLog.favorites} J:${countsForLog.journals} N:${countsForLog.notes}');
            } else {
              appLog('[BG] Page 1 topbar counts unavailable.');
            }
            final List<Message> unread =
                fetchedInbox.where((m) => m.isUnread).toList();
            kDebugPrint('[BG] Found ${unread.length} unread messages');
            if (unread.isNotEmpty) {
              final List<Message> newNotes =
                  unread.where((m) => !shownSet.contains(m.id)).toList();
              if (newNotes.isNotEmpty) {
                didFindNewNotificationContent = true;
              }
              kDebugPrint('[BG] New unread messages: ${newNotes.length}');
              final List<String> shownNewNoteIds = <String>[];
              bool noteProcessingFailed = false;
              for (var msg in newNotes) {
                try {
                  kDebugPrint(
                      '[BG] Processing message: ${msg.id} from ${msg.sender}');
                  final String content =
                      await fetchBackgroundNoteContent(msg.link);
                  await prefs.reload();
                  if (_appForegroundStatePreference
                      .isAppForegroundActive(prefs)) {
                    return Future.value(true);
                  }
                  final String payload = 'note_${msg.id}';
                  final int? badgeNumber = await notification_badge
                      .nextIOSNoteBadgeNumberForNotification();
                  await notificationService.showNotification(
                    stableNotificationIdFromString(msg.id),
                    'New Note from ${msg.sender}',
                    content,
                    payload,
                    'notes',
                    badgeNumber: badgeNumber,
                  );
                  didShowBackgroundNotification = true;
                  await notification_badge
                      .commitIOSNoteBadgeNumber(badgeNumber);
                  shownNewNoteIds.add(msg.id);
                  kDebugPrint('[BG] Notification shown for message ${msg.id}');
                  if (badgeNumber != null) {
                    kDebugPrint('[BG] Badge updated to: $badgeNumber');
                  }
                  await markBackgroundNoteAsUnread(msg);
                  kDebugPrint(
                      '[BG] Message ${msg.id} marked as unread on server');
                } catch (e) {
                  noteProcessingFailed = true;
                  kDebugPrint(
                      '[BG ERROR] Failed to process message ${msg.id}: $e');
                }
              }
              if (shownNewNoteIds.isNotEmpty) {
                await MessageStorage.addShownNoteIds(shownNewNoteIds);
                kDebugPrint(
                    '[BG] Saved ${shownNewNoteIds.length} new message IDs');
              }
              didCompleteNotesCheck = !noteProcessingFailed;
            } else {
              didCompleteNotesCheck = true;
            }
            final fetchedIds = fetchedInbox.map((m) => m.id).toList();
            if (fetchedIds.isNotEmpty) {
              await MessageStorage.addSeenNoteIds(fetchedIds);
              kDebugPrint('[BG] Saved ${fetchedIds.length} seen message IDs');
            }
          } catch (e) {
            appLog('[BG ERROR] Notes check failed: $e');
          }
          appLog('[BG] === Starting NOTIFICATION COUNTS CHECK ===');
          try {
            final counts = currentCounts;
            if (counts != null) {
              kDebugPrint(
                  '[BG] New counts: S:${counts.submissions} W:${counts.watches} C:${counts.comments} F:${counts.favorites} J:${counts.journals} N:${counts.notes}');
              final bool submissionsEnabled =
                  prefs.getBool('drawer_notif_submissions_enabled') ?? true;
              final bool watchesEnabled =
                  prefs.getBool('drawer_notif_watches_enabled') ?? true;
              final bool commentsEnabled =
                  prefs.getBool('drawer_notif_comments_enabled') ?? true;
              final bool favoritesEnabled =
                  prefs.getBool('drawer_notif_favorites_enabled') ?? true;
              final bool journalsEnabled =
                  prefs.getBool('drawer_notif_journals_enabled') ?? true;
              final bool notesEnabled =
                  prefs.getBool('drawer_notif_notes_enabled') ?? true;

              final activitiesStateStore = ActivitiesNotificationStateStore();
              final ActivitiesDiff diff = await activitiesStateStore
                  .recordAndDiffCurrentCounts(
                currentCounts: counts,
              );
              await activitiesStateStore.synchronizeDisabledCounts(
                currentCounts: counts,
                submissionsEnabled: submissionsEnabled,
                watchesEnabled: watchesEnabled,
                commentsEnabled: commentsEnabled,
                favoritesEnabled: favoritesEnabled,
                journalsEnabled: journalsEnabled,
                notesEnabled: notesEnabled,
              );
              kDebugPrint(
                  '[BG] Last-seen counts: S:${diff.previous.submissions} W:${diff.previous.watches} C:${diff.previous.comments} F:${diff.previous.favorites} J:${diff.previous.journals} N:${diff.previous.notes}');
              kDebugPrint(
                  '[BG] Increased by:     S:${diff.increasedBy.submissions} W:${diff.increasedBy.watches} C:${diff.increasedBy.comments} F:${diff.increasedBy.favorites} J:${diff.increasedBy.journals} N:${diff.increasedBy.notes}');

              final decision = _countChangePolicy.notificationDecision(
                diff: diff,
                submissionsEnabled: submissionsEnabled,
                watchesEnabled: watchesEnabled,
                commentsEnabled: commentsEnabled,
                favoritesEnabled: favoritesEnabled,
                journalsEnabled: journalsEnabled,
                notesEnabled: notesEnabled,
              );
              final enabledIncreases = decision.increasedBy;

              final NotificationCounts filteredCounts = NotificationCounts(
                submissions: submissionsEnabled ? counts.submissions : 0,
                watches: watchesEnabled ? counts.watches : 0,
                comments: commentsEnabled ? counts.comments : 0,
                favorites: favoritesEnabled ? counts.favorites : 0,
                journals: journalsEnabled ? counts.journals : 0,
                notes: notesEnabled ? counts.notes : 0,
              );
              final String messageBody = buildNotificationMessage(
                filteredCounts,
                enabledIncreases,
              );

              if (decision.shouldNotify) {
                final bool soundActivitiesEnabled =
                    prefs.getBool('sound_new_activities_enabled') ?? true;
                final bool vibrationActivitiesEnabled =
                    prefs.getBool('vibration_new_activities_enabled') ?? true;
                if (soundActivitiesEnabled || vibrationActivitiesEnabled) {
                  if (!messageBody.contains('(+')) {
                    await activitiesStateStore.acknowledgeCurrentCounts(
                      currentCounts: counts,
                    );
                  } else {
                    didFindNewNotificationContent = true;
                    await prefs.reload();
                    if (_appForegroundStatePreference
                        .isAppForegroundActive(prefs)) {
                      await activitiesStateStore.deferActivityNotification(
                        currentCounts: counts,
                        previousObservedCounts: diff.previous,
                        body: messageBody,
                      );
                      appLog(
                          '[BG] Activity notification deferred for foreground: $messageBody');
                      kDebugPrint(
                          '[BG] Activity notification deferred for foreground: $messageBody');
                    } else {
                      final int activityNotificationId =
                          NotificationService.activityNotificationId;
                      await notification_badge
                          .removePreviousActivityNotification(
                        notificationService,
                        replacingWithId:
                            Platform.isIOS ? activityNotificationId : null,
                      );
                      final int? badgeNumber = await notification_badge
                          .nextIOSActivityBadgeNumberForNotification();
                      await notificationService.showNotification(
                        activityNotificationId,
                        'New FA Activity',
                        messageBody,
                        'fa_activity_$activityNotificationId',
                        'activities',
                        badgeNumber: badgeNumber,
                      );
                      didShowBackgroundNotification = true;
                      await notification_badge
                          .commitIOSActivityBadgeNumber(badgeNumber);
                      await notification_badge.rememberActivityNotification(
                        activityNotificationId,
                      );
                      await activitiesStateStore.markActivityNotificationShown(
                        currentCounts: counts,
                        body: messageBody,
                      );
                      appLog('[BG] Activity notification shown.');
                      kDebugPrint(
                          '[BG] Activity notification shown: $messageBody');
                    }
                  }
                } else {
                  appLog(
                      '[BG] Activities sound+vibration disabled; not showing notification.');
                  await activitiesStateStore.acknowledgeCurrentCounts(
                    currentCounts: counts,
                  );
                }
              } else {
                appLog('[BG] No enabled category increased; not notifying.');
                if (diff.hasAnyIncrease) {
                  await activitiesStateStore.acknowledgeCurrentCounts(
                    currentCounts: counts,
                  );
                }
              }
              didCompleteActivitiesCheck = true;
            } else {
              appLog('[BG] No notification data received from FA');
            }
          } catch (e) {
            appLog('[BG ERROR] Notification counts check failed: $e');
          }
          await _adaptiveBackgroundFetchScheduler
              .updateAdaptiveBackgroundFetchAfterTask(
            didShowNotification: didShowBackgroundNotification,
            completedNoNewContentCheck: didCompleteNotesCheck &&
                didCompleteActivitiesCheck &&
                !didFindNewNotificationContent,
          );
          appLog('[BG] Adaptive background scheduler update completed.');
          await _showBackgroundUpdateNotificationIfNeeded(
            notificationService,
            prefs,
          );
          appLog('[BG] === Task completed successfully ===');
          appLog(
              '[BG] Total duration: ${DateTime.now().difference(startTime).inSeconds}s');
          return Future.value(true);
        } catch (e, stackTrace) {
          appLog('[BG ERROR] Task failed: $e');
          kDebugPrint('[BG ERROR] Stack: $stackTrace');
          if (e.toString().contains('network') ||
              e.toString().contains('timeout') ||
              e.toString().contains('connection') ||
              e.toString().contains('SocketException')) {
            appLog('[BG] Network error detected - will retry');
            return Future.value(false);
          }
          appLog('[BG] Non-network error - marking as complete');
          return Future.value(true);
        }
      }
      appLog('[BG] Unknown task type: $task');
      return Future.value(true);
    } catch (e) {
      appLog('[BG FATAL ERROR] Callback dispatcher crash: $e');
      return Future.value(false);
    }
  }

  Future<void> _showBackgroundUpdateNotificationIfNeeded(
    NotificationService notificationService,
    SharedPreferences prefs,
  ) async {
    try {
      final updateInfo = await fetchLatestAppUpdateInfo();
      if (updateInfo == null || !updateInfo.updateAvailable) return;

      final shownKey =
          'shown_update_notification_for_${updateInfo.currentVersion}';
      await prefs.reload();
      if (prefs.getBool(shownKey) ?? false) return;
      if (_appForegroundStatePreference.isAppForegroundActive(prefs)) return;

      await notificationService.showNotification(
        NotificationService.appUpdateNotificationId,
        'New Update Available!',
        'Tap to open FA Notifier.',
        NotificationService.appUpdatePayload,
        'updates',
      );
      await prefs.setBool(shownKey, true);
      appLog(
        '[BG] Update notification shown for installed version '
        '${updateInfo.currentVersion}; latest version ${updateInfo.latestVersion}',
      );
    } catch (e, st) {
      appLog('[BG ERROR] Update notification check failed: $e');
      kDebugPrint('[BG ERROR] Update notification stack: $st');
    }
  }
}
