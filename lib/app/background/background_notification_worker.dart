import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:fanotifier/app/background/ios_stable_fetch_diagnostics.dart';
import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/core/network/fresh_http_overrides.dart';
import 'package:fanotifier/core/preferences/app_foreground_state_preference.dart';
import 'package:fanotifier/features/drawer/data/app_update_service.dart';
import 'package:fanotifier/features/notes/data/background_inbox_service.dart';
import 'package:fanotifier/features/notes/data/background_note_content_service.dart';
import 'package:fanotifier/features/notes/data/background_note_unread_service.dart';
import 'package:fanotifier/features/notes/data/message_storage.dart';
import 'package:fanotifier/features/notes/domain/background_inbox_models.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notifications/data/activities_notification_state.dart';
import 'package:fanotifier/features/notifications/data/adaptive_background_fetch_scheduler.dart'
    as background_scheduler;
import 'package:fanotifier/features/notifications/data/notification_badge_state.dart'
    as notification_badge;
import 'package:fanotifier/features/notifications/data/notification_service.dart';
import 'package:fanotifier/features/notifications/domain/activity_count_change_policy.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';
import 'package:fanotifier/features/notifications/domain/notification_message_formatter.dart';
import 'package:fanotifier/features/notifications/domain/stable_notification_id.dart';
import 'package:fanotifier/core/network/fa_http.dart';

class BackgroundNotificationExecutionResult {
  const BackgroundNotificationExecutionResult({
    required this.success,
    required this.didExecute,
  });

  final bool success;
  final bool didExecute;
}

class BackgroundNotificationWorker {
  static const ActivityCountChangePolicy _countChangePolicy =
      ActivityCountChangePolicy();
  static const int _unreadRestoreMaxAttempts = 2;
  static const Duration _unreadRestoreAfterReadDelay = Duration(seconds: 1);
  static const Duration _unreadRestoreRetryDelay = Duration(seconds: 2);
  static const MethodChannel _backgroundFetchChannel =
      MethodChannel('app.background_fetch');
  static const String _experimentalIOSFetchEnabledPreferenceKey =
      'experimentalStableIOSBackgroundFetchEnabled';
  static int _nextWorkerRunId = 0;

  BackgroundNotificationWorker({
    required background_scheduler.AdaptiveBackgroundFetchScheduler
        adaptiveBackgroundFetchScheduler,
    AppForegroundStatePreference appForegroundStatePreference =
        const AppForegroundStatePreference(),
    bool requiresIOSExecutionLease = false,
  })  : _adaptiveBackgroundFetchScheduler = adaptiveBackgroundFetchScheduler,
        _appForegroundStatePreference = appForegroundStatePreference,
        _requiresIOSExecutionLease = requiresIOSExecutionLease;

  final background_scheduler.AdaptiveBackgroundFetchScheduler
      _adaptiveBackgroundFetchScheduler;
  final AppForegroundStatePreference _appForegroundStatePreference;
  final bool _requiresIOSExecutionLease;

  Future<bool> _restorePendingUnreadNote(
    PendingNoteUnreadRestore pending, {
    required String source,
    required String runId,
  }) async {
    for (var attempt = 1; attempt <= _unreadRestoreMaxAttempts; attempt++) {
      iosStableFetchDiagnostic(
        'NOTE_UNREAD_ATTEMPT_START',
        <String, Object?>{
          'runId': runId,
          'noteId': pending.noteId,
          'source': source,
          'attempt': attempt,
          'maxAttempts': _unreadRestoreMaxAttempts,
        },
      );
      appLog(
        '[BG_NOTE_UNREAD] noteId=${pending.noteId} source=$source '
        'phase=attempt_start attempt=$attempt/$_unreadRestoreMaxAttempts',
      );
      BackgroundNoteUnreadResult result;
      try {
        result = await restoreBackgroundNoteAsUnread(
          noteId: pending.noteId,
          link: pending.link,
        );
      } catch (error) {
        iosStableFetchDiagnostic(
          'NOTE_UNREAD_ATTEMPT_FINISH',
          <String, Object?>{
            'runId': runId,
            'noteId': pending.noteId,
            'source': source,
            'attempt': attempt,
            'confirmed': false,
            'error': error.runtimeType.toString(),
          },
        );
        appLog(
          '[BG_NOTE_UNREAD] noteId=${pending.noteId} source=$source '
          'phase=attempt_end attempt=$attempt/$_unreadRestoreMaxAttempts '
          'confirmed=false status=none outcome=${error.runtimeType} durationMs=unknown',
        );
        return false;
      }

      appLog(
        '[BG_NOTE_UNREAD] noteId=${pending.noteId} source=$source '
        'phase=attempt_end attempt=$attempt/$_unreadRestoreMaxAttempts '
        'confirmed=${result.success} status=${result.statusCode ?? 'none'} '
        'outcome=${result.outcome.name} '
        'durationMs=${result.duration.inMilliseconds}',
      );
      iosStableFetchDiagnostic(
        'NOTE_UNREAD_ATTEMPT_FINISH',
        <String, Object?>{
          'runId': runId,
          'noteId': pending.noteId,
          'source': source,
          'attempt': attempt,
          'confirmed': result.success,
          'status': result.statusCode,
          'outcome': result.outcome.name,
          'durationMs': result.duration.inMilliseconds,
        },
      );
      if (result.success) {
        try {
          await MessageStorage.removePendingUnreadRestore(pending.noteId);
          appLog(
            '[BG_NOTE_UNREAD] noteId=${pending.noteId} source=$source '
            'phase=pending_cleared confirmed=true',
          );
          iosStableFetchDiagnostic(
            'NOTE_UNREAD_PENDING_CLEARED',
            <String, Object?>{
              'runId': runId,
              'noteId': pending.noteId,
              'source': source,
            },
          );
          return true;
        } catch (error) {
          appLog(
            '[BG_NOTE_UNREAD] noteId=${pending.noteId} source=$source '
            'phase=pending_clear_failed error=${error.runtimeType}',
          );
          return false;
        }
      }

      if (!result.shouldRetryImmediately ||
          attempt == _unreadRestoreMaxAttempts) {
        break;
      }
      await Future<void>.delayed(_unreadRestoreRetryDelay);
    }

    appLog(
      '[BG_NOTE_UNREAD] noteId=${pending.noteId} source=$source '
      'phase=pending_retained confirmed=false',
    );
    iosStableFetchDiagnostic(
      'NOTE_UNREAD_PENDING_RETAINED',
      <String, Object?>{
        'runId': runId,
        'noteId': pending.noteId,
        'source': source,
      },
    );
    return false;
  }

  Future<void> _logActiveNotificationSnapshot(
    NotificationService notificationService, {
    required String runId,
    required String noteId,
    required String phase,
  }) async {
    if (!Platform.isIOS || !await isIOSStableFetchDiagnosticsEnabled()) return;
    try {
      final notifications = await notificationService
          .getActiveNotificationDiagnostics()
          .timeout(const Duration(seconds: 2));
      iosStableFetchDiagnostic(
        'DELIVERED_NOTIFICATIONS_SNAPSHOT',
        <String, Object?>{
          'runId': runId,
          'noteId': noteId,
          'phase': phase,
          'count': notifications.length,
          'notifications': notifications,
        },
      );
    } catch (error) {
      iosStableFetchDiagnostic(
        'DELIVERED_NOTIFICATIONS_SNAPSHOT_ERROR',
        <String, Object?>{
          'runId': runId,
          'noteId': noteId,
          'phase': phase,
          'error': error.runtimeType.toString(),
        },
      );
    }
  }

  Future<bool> execute(
    String task,
    Map<String, dynamic>? inputData,
  ) async {
    final executionResult = await executeForExperimental(
      task,
      inputData,
    );
    return executionResult.success;
  }

  Future<BackgroundNotificationExecutionResult> executeForExperimental(
    String task,
    Map<String, dynamic>? inputData,
  ) async {
    final runId =
        'worker-${DateTime.now().millisecondsSinceEpoch}-${++_nextWorkerRunId}';
    final executionStopwatch = Stopwatch()..start();
    iosStableFetchDiagnostic(
      'WORKER_DISPATCH',
      <String, Object?>{
        'runId': runId,
        'task': task,
        'requiresIOSExecutionLease': _requiresIOSExecutionLease,
      },
    );
    String? executionLeaseToken;
    bool executionLeaseProtocolAvailable = false;
    if (Platform.isIOS) {
      try {
        executionLeaseToken = await _backgroundFetchChannel
            .invokeMethod<String>('acquireExecution');
        executionLeaseProtocolAvailable = true;
      } catch (_) {}
      if (!executionLeaseProtocolAvailable) {
        var requiresExecutionLease = _requiresIOSExecutionLease;
        if (!requiresExecutionLease) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.reload();
            requiresExecutionLease =
                prefs.getBool(_experimentalIOSFetchEnabledPreferenceKey) ??
                    false;
          } catch (_) {}
        }
        if (requiresExecutionLease) {
          iosStableFetchDiagnostic(
            'WORKER_SKIPPED',
            <String, Object?>{
              'runId': runId,
              'reason': 'leaseProtocolUnavailable',
            },
          );
          return const BackgroundNotificationExecutionResult(
            success: false,
            didExecute: false,
          );
        }
      }
      if (executionLeaseProtocolAvailable && executionLeaseToken == null) {
        iosStableFetchDiagnostic(
          'WORKER_SKIPPED',
          <String, Object?>{
            'runId': runId,
            'reason': 'leaseDenied',
          },
        );
        return const BackgroundNotificationExecutionResult(
          success: true,
          didExecute: false,
        );
      }
      if (executionLeaseToken?.isEmpty == true) {
        executionLeaseToken = null;
      }
    }

    try {
      final success = await _executeInternal(
        task,
        inputData,
        runId: runId,
      );
      executionStopwatch.stop();
      iosStableFetchDiagnostic(
        'WORKER_FINISH',
        <String, Object?>{
          'runId': runId,
          'success': success,
          'didExecute': true,
          'durationMs': executionStopwatch.elapsedMilliseconds,
        },
      );
      return BackgroundNotificationExecutionResult(
        success: success,
        didExecute: true,
      );
    } finally {
      final token = executionLeaseToken;
      if (token != null) {
        try {
          await _backgroundFetchChannel.invokeMethod<void>(
            'releaseExecution',
            <String, String>{'token': token},
          );
        } catch (_) {}
      }
    }
  }

  Future<bool> _executeInternal(
    String task,
    Map<String, dynamic>? inputData, {
    required String runId,
  }) async {
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
      iosStableFetchDiagnostic(
        'WORKER_STAGE',
        <String, Object?>{
          'runId': runId,
          'stage': 'notificationServiceReady',
        },
      );
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
          final preflightStopwatch = Stopwatch()..start();
          bool pendingUnreadRestoreFailed = false;
          final pendingUnreadRestores =
              await MessageStorage.getPendingUnreadRestores();
          if (pendingUnreadRestores.isNotEmpty) {
            appLog(
              '[BG_NOTE_UNREAD] phase=pending_drain_start '
              'count=${pendingUnreadRestores.length}',
            );
          }
          for (final pending in pendingUnreadRestores) {
            await prefs.reload();
            if (_appForegroundStatePreference.isAppForegroundActive(prefs)) {
              return Future.value(true);
            }
            final restored = await _restorePendingUnreadNote(
              pending,
              source: 'pending_cycle',
              runId: runId,
            );
            if (!restored) {
              pendingUnreadRestoreFailed = true;
              if (FaRequestCoordinator
                      .instance.status.value.remaining >
                  Duration.zero) {
                break;
              }
            }
          }
          final currentVersionAllowed = await isCurrentAppVersionAllowed();
          preflightStopwatch.stop();
          iosStableFetchDiagnostic(
            'WORKER_STAGE',
            <String, Object?>{
              'runId': runId,
              'stage': 'pendingAndVersionCheck',
              'durationMs': preflightStopwatch.elapsedMilliseconds,
              'pendingCount': pendingUnreadRestores.length,
              'pendingFailed': pendingUnreadRestoreFailed,
              'currentVersionAllowed': currentVersionAllowed,
            },
          );
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
            bool noteProcessingFailed = pendingUnreadRestoreFailed;
            final pendingRetryWait =
                FaRequestCoordinator.instance.status.value.remaining;
            if (pendingRetryWait > Duration.zero) {
              throw StateError(
                'Pending note unread restore deferred for '
                '${pendingRetryWait.inMilliseconds}ms',
              );
            }
            final Set<String> shownSet = await MessageStorage.getShownNoteIds();
            final Set<String> seenSet = await MessageStorage.getSeenNoteIds();
            final inboxStopwatch = Stopwatch()..start();
            final BackgroundInboxSnapshot snapshot =
                await fetchBackgroundInboxSnapshot(
              shownNoteIds: shownSet,
              seenNoteIds: seenSet,
            );
            inboxStopwatch.stop();
            final List<Message> fetchedInbox = snapshot.messages;
            currentCounts = snapshot.topbarCounts;
            iosStableFetchDiagnostic(
              'WORKER_STAGE',
              <String, Object?>{
                'runId': runId,
                'stage': 'inboxFetched',
                'durationMs': inboxStopwatch.elapsedMilliseconds,
                'messageCount': fetchedInbox.length,
                'fetchedPage2': snapshot.fetchedPage2,
              },
            );
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
              final claimedNoteIds = <String>{...shownSet};
              final List<Message> newNotes =
                  unread.where((m) => claimedNoteIds.add(m.id)).toList();
              if (newNotes.isNotEmpty) {
                didFindNewNotificationContent = true;
              }
              kDebugPrint('[BG] New unread messages: ${newNotes.length}');
              for (var msg in newNotes) {
                final noteRetryWait =
                    FaRequestCoordinator.instance.status.value.remaining;
                if (noteRetryWait > Duration.zero) {
                  noteProcessingFailed = true;
                  iosStableFetchDiagnostic(
                    'NOTE_PROCESSING_DEFERRED',
                    <String, Object?>{
                      'runId': runId,
                      'noteId': msg.id,
                      'remainingMs': noteRetryWait.inMilliseconds,
                    },
                  );
                  break;
                }
                PendingNoteUnreadRestore? pendingRestore;
                var restorationAttempted = false;
                var claimed = false;
                var notificationShown = false;
                try {
                  kDebugPrint(
                      '[BG] Processing message: ${msg.id} from ${msg.sender}');
                  final queuedRestore =
                      await MessageStorage.addPendingUnreadRestore(
                    noteId: msg.id,
                    link: msg.link,
                  );
                  pendingRestore = queuedRestore;
                  appLog(
                    '[BG_NOTE_UNREAD] noteId=${msg.id} source=new_note '
                    'phase=pending_persisted',
                  );
                  iosStableFetchDiagnostic(
                    'NOTE_PENDING_PERSISTED',
                    <String, Object?>{
                      'runId': runId,
                      'noteId': msg.id,
                    },
                  );

                  final contentStopwatch = Stopwatch()..start();
                  late final String content;
                  try {
                    content = await fetchBackgroundNoteContent(msg.link);
                    contentStopwatch.stop();
                    appLog(
                      '[BG_NOTE_CONTENT] noteId=${msg.id} success=true status=200 '
                      'durationMs=${contentStopwatch.elapsedMilliseconds} '
                      'bodyLength=${content.length}',
                    );
                    iosStableFetchDiagnostic(
                      'NOTE_CONTENT_FINISH',
                      <String, Object?>{
                        'runId': runId,
                        'noteId': msg.id,
                        'success': true,
                        'status': 200,
                        'durationMs': contentStopwatch.elapsedMilliseconds,
                        'bodyLength': content.length,
                      },
                    );
                  } catch (error) {
                    contentStopwatch.stop();
                    appLog(
                      '[BG_NOTE_CONTENT] noteId=${msg.id} '
                      'success=false status=unknown '
                      'durationMs=${contentStopwatch.elapsedMilliseconds} '
                      'error=${error.runtimeType}',
                    );
                    iosStableFetchDiagnostic(
                      'NOTE_CONTENT_FINISH',
                      <String, Object?>{
                        'runId': runId,
                        'noteId': msg.id,
                        'success': false,
                        'durationMs': contentStopwatch.elapsedMilliseconds,
                        'error': error.runtimeType.toString(),
                      },
                    );
                    rethrow;
                  }

                  restorationAttempted = true;
                  await Future<void>.delayed(_unreadRestoreAfterReadDelay);
                  final restored = await _restorePendingUnreadNote(
                    queuedRestore,
                    source: 'new_note',
                    runId: runId,
                  );
                  if (!restored) {
                    noteProcessingFailed = true;
                  }

                  await prefs.reload();
                  if (_appForegroundStatePreference
                      .isAppForegroundActive(prefs)) {
                    return Future.value(true);
                  }
                  final String payload = 'note_${msg.id}';
                  claimed = await MessageStorage.claimUnshownNoteId(msg.id);
                  appLog(
                    '[BG_NOTE_CLAIM] noteId=${msg.id} claimed=$claimed',
                  );
                  iosStableFetchDiagnostic(
                    'NOTE_NOTIFICATION_CLAIM',
                    <String, Object?>{
                      'runId': runId,
                      'noteId': msg.id,
                      'claimed': claimed,
                    },
                  );
                  if (!claimed) continue;
                  final int? badgeNumber = await notification_badge
                      .nextIOSNoteBadgeNumberForNotification();
                  final notificationId = stableNotificationIdFromString(msg.id);
                  await _logActiveNotificationSnapshot(
                    notificationService,
                    runId: runId,
                    noteId: msg.id,
                    phase: 'beforeShow',
                  );
                  final notificationStopwatch = Stopwatch()..start();
                  try {
                    await notificationService.showNotification(
                      notificationId,
                      'New Note from ${msg.sender}',
                      content,
                      payload,
                      'notes',
                      badgeNumber: badgeNumber,
                    );
                    notificationShown = true;
                    notificationStopwatch.stop();
                    appLog(
                      '[BG_NOTE_NOTIFICATION] noteId=${msg.id} '
                      'notificationId=$notificationId success=true '
                      'durationMs=${notificationStopwatch.elapsedMilliseconds}',
                    );
                    iosStableFetchDiagnostic(
                      'NOTE_NOTIFICATION_FINISH',
                      <String, Object?>{
                        'runId': runId,
                        'noteId': msg.id,
                        'notificationId': notificationId,
                        'success': true,
                        'durationMs':
                            notificationStopwatch.elapsedMilliseconds,
                      },
                    );
                    await _logActiveNotificationSnapshot(
                      notificationService,
                      runId: runId,
                      noteId: msg.id,
                      phase: 'afterShow',
                    );
                  } catch (error) {
                    notificationStopwatch.stop();
                    appLog(
                      '[BG_NOTE_NOTIFICATION] noteId=${msg.id} '
                      'notificationId=$notificationId success=false '
                      'durationMs=${notificationStopwatch.elapsedMilliseconds} '
                      'error=${error.runtimeType}',
                    );
                    iosStableFetchDiagnostic(
                      'NOTE_NOTIFICATION_FINISH',
                      <String, Object?>{
                        'runId': runId,
                        'noteId': msg.id,
                        'notificationId': notificationId,
                        'success': false,
                        'durationMs':
                            notificationStopwatch.elapsedMilliseconds,
                        'error': error.runtimeType.toString(),
                      },
                    );
                    rethrow;
                  }
                  didShowBackgroundNotification = true;
                  await notification_badge
                      .commitIOSNoteBadgeNumber(badgeNumber);
                  kDebugPrint('[BG] Notification shown for message ${msg.id}');
                  if (badgeNumber != null) {
                    kDebugPrint('[BG] Badge updated to: $badgeNumber');
                  }
                } catch (error) {
                  noteProcessingFailed = true;
                  if (claimed && !notificationShown) {
                    try {
                      await MessageStorage.releaseClaimedNoteId(msg.id);
                      appLog(
                        '[BG_NOTE_CLAIM] noteId=${msg.id} phase=released '
                        'notificationShown=false',
                      );
                    } catch (releaseError) {
                      appLog(
                        '[BG_NOTE_CLAIM] noteId=${msg.id} '
                        'phase=release_failed error=${releaseError.runtimeType}',
                      );
                    }
                  }
                  final pending = pendingRestore;
                  if (pending != null && !restorationAttempted) {
                    final restored = await _restorePendingUnreadNote(
                      pending,
                      source: 'content_failure',
                      runId: runId,
                    );
                    if (!restored) {
                      noteProcessingFailed = true;
                    }
                  }
                  kDebugPrint(
                    '[BG ERROR] Failed to process message ${msg.id}: '
                    '${error.runtimeType}',
                  );
                }
              }
            }
            didCompleteNotesCheck = !noteProcessingFailed;
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
              final RecordedActivitiesDiff recordedDiff =
                  await activitiesStateStore.recordAndDiffCurrentCounts(
                currentCounts: counts,
              );
              final ActivitiesDiff observedDiff = recordedDiff.observed;
              final ActivitiesDiff unacknowledgedDiff =
                  recordedDiff.unacknowledged;
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
                  '[BG] Last-seen counts: S:${observedDiff.previous.submissions} W:${observedDiff.previous.watches} C:${observedDiff.previous.comments} F:${observedDiff.previous.favorites} J:${observedDiff.previous.journals} N:${observedDiff.previous.notes}');
              kDebugPrint(
                  '[BG] Increased by:     S:${observedDiff.increasedBy.submissions} W:${observedDiff.increasedBy.watches} C:${observedDiff.increasedBy.comments} F:${observedDiff.increasedBy.favorites} J:${observedDiff.increasedBy.journals} N:${observedDiff.increasedBy.notes}');

              final displayDecision = _countChangePolicy.notificationDecision(
                diff: unacknowledgedDiff,
                submissionsEnabled: submissionsEnabled,
                watchesEnabled: watchesEnabled,
                commentsEnabled: commentsEnabled,
                favoritesEnabled: favoritesEnabled,
                journalsEnabled: journalsEnabled,
                notesEnabled: notesEnabled,
              );
              final enabledIncreases = displayDecision.increasedBy;

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

              if (displayDecision.shouldNotify) {
                final bool alreadyShown =
                    await activitiesStateStore.areCurrentCountsLastShown(
                  currentCounts: counts,
                  submissionsEnabled: submissionsEnabled,
                  watchesEnabled: watchesEnabled,
                  commentsEnabled: commentsEnabled,
                  favoritesEnabled: favoritesEnabled,
                  journalsEnabled: journalsEnabled,
                  notesEnabled: notesEnabled,
                );
                if (!alreadyShown && messageBody.contains('(+')) {
                  didFindNewNotificationContent = true;
                  await prefs.reload();
                  if (_appForegroundStatePreference
                      .isAppForegroundActive(prefs)) {
                    await activitiesStateStore.deferActivityNotification(
                      currentCounts: counts,
                      previousObservedCounts: observedDiff.previous,
                      body: messageBody,
                    );
                    appLog(
                        '[BG] Activity notification deferred for foreground: $messageBody');
                    kDebugPrint(
                        '[BG] Activity notification deferred for foreground: $messageBody');
                  } else {
                    final int activityNotificationId =
                        NotificationService.activityNotificationId;
                    await notification_badge.removePreviousActivityNotification(
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
                    iosStableFetchDiagnostic(
                      'ACTIVITY_NOTIFICATION_SHOWN',
                      <String, Object?>{
                        'runId': runId,
                        'notificationId': activityNotificationId,
                        'badgeNumber': badgeNumber,
                      },
                    );
                    await _logActiveNotificationSnapshot(
                      notificationService,
                      runId: runId,
                      noteId: 'activity',
                      phase: 'afterActivityShow',
                    );
                    didShowBackgroundNotification = true;
                    await activitiesStateStore.markActivityNotificationShown(
                      currentCounts: counts,
                      body: messageBody,
                    );
                    await notification_badge
                        .commitIOSActivityBadgeNumber(badgeNumber);
                    await notification_badge.rememberActivityNotification(
                      activityNotificationId,
                    );
                    appLog('[BG] Activity notification shown.');
                    kDebugPrint(
                        '[BG] Activity notification shown: $messageBody');
                  }
                }
              } else {
                appLog('[BG] No enabled category increased; not notifying.');
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
          iosStableFetchDiagnostic(
            'WORKER_STAGE',
            <String, Object?>{
              'runId': runId,
              'stage': 'adaptiveSchedulerUpdated',
              'didShowNotification': didShowBackgroundNotification,
              'didCompleteNotesCheck': didCompleteNotesCheck,
              'didCompleteActivitiesCheck': didCompleteActivitiesCheck,
              'didFindNewNotificationContent':
                  didFindNewNotificationContent,
            },
          );
          final updateStopwatch = Stopwatch()..start();
          await _showBackgroundUpdateNotificationIfNeeded(
            notificationService,
            prefs,
          );
          updateStopwatch.stop();
          iosStableFetchDiagnostic(
            'WORKER_STAGE',
            <String, Object?>{
              'runId': runId,
              'stage': 'updateCheckFinished',
              'durationMs': updateStopwatch.elapsedMilliseconds,
            },
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
