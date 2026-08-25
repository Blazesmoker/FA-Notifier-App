import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/core/analytics/app_analytics.dart';
import 'package:fanotifier/core/crash_reporting/app_crash_reporter.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/core/network/fresh_http_overrides.dart';
import 'package:fanotifier/core/preferences/app_foreground_state_preference.dart';
import 'package:fanotifier/core/preferences/privacy_settings_preference.dart';
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

class BackgroundNotificationExecutionCancelled implements Exception {
  const BackgroundNotificationExecutionCancelled();
}

class BackgroundNotificationExecutionCancellation {
  final Set<CancelToken> _dioCancelTokens = <CancelToken>{};
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    FAHttp.reset();
    for (final token in _dioCancelTokens.toList()) {
      if (!token.isCancelled) {
        token.cancel('Background execution expired');
      }
    }
    _dioCancelTokens.clear();
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const BackgroundNotificationExecutionCancelled();
    }
  }

  Future<T> runDioOperation<T>(
    Future<T> Function(CancelToken cancelToken) operation, {
    DateTime? finishBy,
    required String timeoutReason,
  }) async {
    throwIfCancelled();
    final cancelToken = CancelToken();
    _dioCancelTokens.add(cancelToken);
    try {
      final future = operation(cancelToken);
      if (finishBy == null) return await future;
      final timeout = finishBy.difference(DateTime.now());
      if (timeout <= Duration.zero) {
        if (!cancelToken.isCancelled) cancelToken.cancel(timeoutReason);
        throw TimeoutException(timeoutReason);
      }
      return await future.timeout(
        timeout,
        onTimeout: () {
          if (!cancelToken.isCancelled) cancelToken.cancel(timeoutReason);
          throw TimeoutException(timeoutReason);
        },
      );
    } finally {
      _dioCancelTokens.remove(cancelToken);
    }
  }
}

class _BackgroundNotificationRunResult {
  const _BackgroundNotificationRunResult({
    required this.success,
    this.contentOutcome,
    this.analyticsOutcome,
  });

  final bool success;
  final background_scheduler.BackgroundContentFetchOutcome? contentOutcome;
  final NotificationCheckOutcome? analyticsOutcome;
}

class _NoteDeliveryWindow {
  const _NoteDeliveryWindow(this.taskDeadline);

  static const Duration _closingAllowance = Duration(milliseconds: 900);
  static const Duration _noticeBaseAllowance = Duration(milliseconds: 500);
  static const int _noticeAllowanceMilliseconds = 250;
  static const Duration _contentAttemptAllowance = Duration(seconds: 4);
  static const Duration _unreadWorkAllowance = Duration(seconds: 4);

  final DateTime? taskDeadline;

  DateTime? unreadFinishBy(int noticesWaiting) {
    final deadline = taskDeadline;
    if (deadline == null) return null;
    final noticeAllowance = Duration(
      milliseconds: _noticeAllowanceMilliseconds *
          (noticesWaiting < 0 ? 0 : noticesWaiting),
    );
    return deadline.subtract(
      _closingAllowance + _noticeBaseAllowance + noticeAllowance,
    );
  }

  DateTime? contentFinishBy(int noticesWaiting) {
    return unreadFinishBy(noticesWaiting)?.subtract(_unreadWorkAllowance);
  }

  bool canFetchFullNote(
    int noticesWaiting, {
    required Duration requestGateWait,
  }) {
    final finishBy = contentFinishBy(noticesWaiting);
    if (finishBy == null) return true;
    return finishBy.difference(DateTime.now()) >=
        requestGateWait + _contentAttemptAllowance;
  }

  bool get canShowUpdateNotification {
    final deadline = taskDeadline;
    if (deadline == null) return true;
    return deadline.difference(DateTime.now()) >
        _closingAllowance + _noticeBaseAllowance;
  }

  bool get canStartNotice {
    final deadline = taskDeadline;
    if (deadline == null) return true;
    return deadline.difference(DateTime.now()) > _closingAllowance;
  }
}

class _PreparedNoteAlert {
  _PreparedNoteAlert({required this.message});

  final Message message;
  String? fullBody;
}

class _ActivitySnapshotResult {
  const _ActivitySnapshotResult({
    required this.completed,
    required this.foundNewContent,
  });

  final bool completed;
  final bool foundNewContent;
}

class BackgroundNotificationWorker {
  static const ActivityCountChangePolicy _countChangePolicy =
      ActivityCountChangePolicy();
  static const Duration _backgroundUpdatePreflightTimeout =
      Duration(seconds: 5);
  static const Duration _iosTaskCompletionTimeout = Duration(seconds: 29);
  static const MethodChannel _backgroundFetchChannel =
      MethodChannel('app.background_fetch');

  BackgroundNotificationWorker({
    required this.adaptiveBackgroundFetchScheduler,
    this.appForegroundStatePreference =
        const AppForegroundStatePreference(),
  });

  final background_scheduler.AdaptiveBackgroundFetchScheduler
      adaptiveBackgroundFetchScheduler;
  final AppForegroundStatePreference appForegroundStatePreference;
  bool _notificationShownThisRun = false;

  Future<bool> _restorePendingUnreadBatch({
    required BackgroundNotificationExecutionCancellation cancellation,
    DateTime? finishBy,
  }) async {
    cancellation.throwIfCancelled();
    final pendingUnreadRestores =
        await MessageStorage.getPendingUnreadRestores();
    if (pendingUnreadRestores.isEmpty) return true;
    final noteIds = pendingUnreadRestores
        .map((pending) => pending.noteId.trim())
        .where((noteId) => noteId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (noteIds.isEmpty) return true;

    appLog(
      '[BG_NOTE_UNREAD] phase=bulk_attempt_start count=${noteIds.length}',
    );
    try {
      final result = await cancellation.runDioOperation(
        (cancelToken) => restoreBackgroundNotesAsUnread(
          noteIds: noteIds,
          cancelToken: cancelToken,
        ),
        finishBy: finishBy,
        timeoutReason: 'Bulk unread restoration budget expired',
      );
      cancellation.throwIfCancelled();
      appLog(
        '[BG_NOTE_UNREAD] phase=bulk_attempt_end count=${noteIds.length} '
        'confirmed=${result.success} status=${result.statusCode ?? 'none'} '
        'outcome=${result.outcome.name} '
        'durationMs=${result.duration.inMilliseconds}',
      );
      if (!result.success) return false;
      try {
        await MessageStorage.removePendingUnreadRestores(noteIds);
        appLog(
          '[BG_NOTE_UNREAD] phase=bulk_pending_cleared '
          'count=${noteIds.length}',
        );
        return true;
      } catch (error) {
        appLog(
          '[BG_NOTE_UNREAD] phase=bulk_pending_clear_failed '
          'count=${noteIds.length} error=${error.runtimeType}',
        );
        return false;
      }
    } catch (error) {
      cancellation.throwIfCancelled();
      appLog(
        '[BG_NOTE_UNREAD] phase=bulk_attempt_end count=${noteIds.length} '
        'confirmed=false status=none outcome=${error.runtimeType} '
        'durationMs=unknown',
      );
      return false;
    }
  }

  String _fallbackNoteBody(_PreparedNoteAlert alert) {
    final subject = alert.message.subject.trim();
    if (subject.isNotEmpty && subject.toLowerCase() != 'no subject') {
      return subject;
    }
    return 'Open FA Notifier to read this note.';
  }

  Future<bool> _deliverPreparedNoteAlert({
    required _PreparedNoteAlert alert,
    required NotificationService notificationService,
    required SharedPreferences prefs,
    required BackgroundNotificationExecutionCancellation cancellation,
  }) async {
    final noteId = alert.message.id;
    final richBody = alert.fullBody?.trim();
    final hasRichBody = richBody != null && richBody.isNotEmpty;
    final deliveryMode = hasRichBody ? 'full_content' : 'inbox_only';
    var claimed = false;
    var notificationShown = false;
    try {
      cancellation.throwIfCancelled();
      await prefs.reload();
      if (appForegroundStatePreference.isAppForegroundActive(prefs)) {
        return false;
      }

      claimed = await MessageStorage.claimUnshownNoteId(noteId);
      appLog(
        '[BG_NOTE_CLAIM] noteId=$noteId claimed=$claimed mode=$deliveryMode',
      );
      if (!claimed) return true;

      cancellation.throwIfCancelled();
      final badgeNumber =
          await notification_badge.nextIOSNoteBadgeNumberForNotification();
      final notificationId = stableNotificationIdFromString(noteId);
      final sender = alert.message.sender.trim();
      final titleSender = sender.isEmpty ? 'Unknown sender' : sender;
      final notificationStopwatch = Stopwatch()..start();
      await notificationService.showNotification(
        notificationId,
        'New Note from $titleSender',
        hasRichBody ? richBody : _fallbackNoteBody(alert),
        'note_$noteId',
        'notes',
        badgeNumber: badgeNumber,
      );
      notificationShown = true;
      _notificationShownThisRun = true;
      await appAnalytics.logNotificationDisplayed(
        executionContext: NotificationExecutionContext.backgroundPeriodic,
        notificationType: 'note',
      );
      notificationStopwatch.stop();
      await notification_badge.commitIOSNoteBadgeNumber(badgeNumber);
      appLog(
        '[BG_NOTE_NOTIFICATION] noteId=$noteId '
        'notificationId=$notificationId success=true mode=$deliveryMode '
        'durationMs=${notificationStopwatch.elapsedMilliseconds}',
      );
      cancellation.throwIfCancelled();
      return true;
    } catch (error) {
      if (claimed && !notificationShown) {
        try {
          await MessageStorage.releaseClaimedNoteId(noteId);
          appLog(
            '[BG_NOTE_CLAIM] noteId=$noteId phase=released '
            'notificationShown=false mode=$deliveryMode',
          );
        } catch (releaseError) {
          appLog(
            '[BG_NOTE_CLAIM] noteId=$noteId phase=release_failed '
            'error=${releaseError.runtimeType}',
          );
        }
      }
      if (error is BackgroundNotificationExecutionCancelled ||
          cancellation.isCancelled) {
        throw const BackgroundNotificationExecutionCancelled();
      }
      appLog(
        '[BG_NOTE_NOTIFICATION] noteId=$noteId success=false '
        'mode=$deliveryMode error=${error.runtimeType}',
      );
      return false;
    }
  }

  Future<bool> _deliverPreparedNoteAlerts({
    required List<_PreparedNoteAlert> alerts,
    required _NoteDeliveryWindow deliveryWindow,
    required NotificationService notificationService,
    required SharedPreferences prefs,
    required BackgroundNotificationExecutionCancellation cancellation,
  }) async {
    var allDelivered = true;
    for (final alert in alerts) {
      cancellation.throwIfCancelled();
      if (!deliveryWindow.canStartNotice) {
        allDelivered = false;
        break;
      }
      final delivered = await _deliverPreparedNoteAlert(
        alert: alert,
        notificationService: notificationService,
        prefs: prefs,
        cancellation: cancellation,
      );
      if (!delivered) allDelivered = false;
    }
    return allDelivered;
  }

  Future<_ActivitySnapshotResult> _processActivitySnapshot({
    required NotificationCounts? counts,
    required NotificationService notificationService,
    required SharedPreferences prefs,
    required BackgroundNotificationExecutionCancellation cancellation,
  }) async {
    cancellation.throwIfCancelled();
    if (counts == null) {
      appLog('[BG] No notification data received from FA');
      return const _ActivitySnapshotResult(
        completed: false,
        foundNewContent: false,
      );
    }

    kDebugPrint(
      '[BG] New counts: S:${counts.submissions} W:${counts.watches} '
      'C:${counts.comments} F:${counts.favorites} J:${counts.journals} '
      'N:${counts.notes}',
    );
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
    final recordedDiff = await activitiesStateStore.recordAndDiffCurrentCounts(
      currentCounts: counts,
    );
    final observedDiff = recordedDiff.observed;
    final unacknowledgedDiff = recordedDiff.unacknowledged;
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
      '[BG] Last-seen counts: S:${observedDiff.previous.submissions} '
      'W:${observedDiff.previous.watches} '
      'C:${observedDiff.previous.comments} '
      'F:${observedDiff.previous.favorites} '
      'J:${observedDiff.previous.journals} '
      'N:${observedDiff.previous.notes}',
    );
    kDebugPrint(
      '[BG] Increased by: S:${observedDiff.increasedBy.submissions} '
      'W:${observedDiff.increasedBy.watches} '
      'C:${observedDiff.increasedBy.comments} '
      'F:${observedDiff.increasedBy.favorites} '
      'J:${observedDiff.increasedBy.journals} '
      'N:${observedDiff.increasedBy.notes}',
    );
    var foundNewContent = observedDiff.hasAnyIncrease;
    final displayDecision = _countChangePolicy.notificationDecision(
      diff: unacknowledgedDiff,
      submissionsEnabled: submissionsEnabled,
      watchesEnabled: watchesEnabled,
      commentsEnabled: commentsEnabled,
      favoritesEnabled: favoritesEnabled,
      journalsEnabled: journalsEnabled,
      notesEnabled: notesEnabled,
    );
    final filteredCounts = NotificationCounts(
      submissions: submissionsEnabled ? counts.submissions : 0,
      watches: watchesEnabled ? counts.watches : 0,
      comments: commentsEnabled ? counts.comments : 0,
      favorites: favoritesEnabled ? counts.favorites : 0,
      journals: journalsEnabled ? counts.journals : 0,
      notes: notesEnabled ? counts.notes : 0,
    );
    final messageBody = buildNotificationMessage(
      filteredCounts,
      displayDecision.increasedBy,
    );

    if (displayDecision.shouldNotify) {
      final alreadyShown =
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
        foundNewContent = true;
        await prefs.reload();
        cancellation.throwIfCancelled();
        if (appForegroundStatePreference.isAppForegroundActive(prefs)) {
          await activitiesStateStore.deferActivityNotification(
            currentCounts: counts,
            previousObservedCounts: observedDiff.previous,
            body: messageBody,
          );
          appLog(
            '[BG] Activity notification deferred for foreground: '
            '$messageBody',
          );
          kDebugPrint(
            '[BG] Activity notification deferred for foreground: '
            '$messageBody',
          );
        } else {
          final activityNotificationId =
              NotificationService.activityNotificationId;
          await notification_badge.removePreviousActivityNotification(
            notificationService,
            replacingWithId: Platform.isIOS ? activityNotificationId : null,
          );
          final badgeNumber = await notification_badge
              .nextIOSActivityBadgeNumberForNotification();
          await notificationService.showNotification(
            activityNotificationId,
            'New FA Activity',
            messageBody,
            'fa_activity_$activityNotificationId',
            'activities',
            badgeNumber: badgeNumber,
          );
          _notificationShownThisRun = true;
          await appAnalytics.logNotificationDisplayed(
            executionContext: NotificationExecutionContext.backgroundPeriodic,
            notificationType: 'activity',
          );
          await activitiesStateStore.markActivityNotificationShown(
            currentCounts: counts,
            body: messageBody,
          );
          await notification_badge.commitIOSActivityBadgeNumber(badgeNumber);
          await notification_badge.rememberActivityNotification(
            activityNotificationId,
          );
          cancellation.throwIfCancelled();
          appLog('[BG] Activity notification shown.');
          kDebugPrint('[BG] Activity notification shown: $messageBody');
        }
      } else if (alreadyShown &&
          messageBody.contains('(+') &&
          Platform.isIOS) {
        final presence =
            await notification_badge.inspectIOSActivityNotificationPresence(
          notificationService,
        );
        if (presence.shouldRestore) {
          final activityNotificationId = presence.notificationId ??
              NotificationService.activityNotificationId;
          final badgeNumber = await notification_badge
              .nextIOSActivityBadgeNumberForNotification();
          await notificationService.showNotification(
            activityNotificationId,
            'New FA Activity',
            messageBody,
            'fa_activity_$activityNotificationId',
            'activities',
            badgeNumber: badgeNumber,
          );
          _notificationShownThisRun = true;
          await appAnalytics.logNotificationDisplayed(
            executionContext: NotificationExecutionContext.backgroundPeriodic,
            notificationType: 'activity',
          );
          await notification_badge
              .markIOSActivityNotificationRestored(badgeNumber);
          cancellation.throwIfCancelled();
        } else if (presence.inspectionSucceeded &&
            !presence.delivered &&
            presence.restoredForCurrent) {
          await notification_badge.clearMissingIOSActivityNotificationBadge();
        }
      }
    } else {
      appLog('[BG] No enabled category increased; not notifying.');
    }

    return _ActivitySnapshotResult(
      completed: true,
      foundNewContent: foundNewContent,
    );
  }

  Future<bool> execute(
    String task,
    Map<String, dynamic>? _,
  ) async {
    final taskStartedAt = DateTime.now();
    _notificationShownThisRun = false;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final crashlyticsEnabled =
          (await SharedPreferences.getInstance()).getBool(
        PrivacySettingsPreference.crashlyticsEnabledKey,
      ) ??
              false;
      await appCrashReporter.initializeBackgroundIsolate(
        collectionEnabled: crashlyticsEnabled,
      );
    } catch (error, stackTrace) {
      try {
        await appCrashReporter.recordNonFatal(
          error,
          stackTrace,
          reason: 'background_worker_initialization_failed',
          executionContext: 'background_periodic',
        );
      } catch (_) {}
      return false;
    }
    final taskDeadline = Platform.isIOS
        ? taskStartedAt.add(_iosTaskCompletionTimeout)
        : null;
    final cancellation = BackgroundNotificationExecutionCancellation();
    String? executionLeaseToken;

    Future<void> releaseExecutionLease() async {
      final token = executionLeaseToken;
      if (token == null) return;
      executionLeaseToken = null;
      try {
        await _backgroundFetchChannel.invokeMethod<void>(
          'releaseExecution',
          <String, Object>{
            'token': token,
          },
        );
      } catch (_) {}
    }

    Future<bool> runTask() async {
      if (Platform.isIOS) {
        try {
          executionLeaseToken = await _backgroundFetchChannel
              .invokeMethod<String>('acquireExecution');
          if (executionLeaseToken == null) {
            appLog('[BG] iOS execution lease unavailable; task skipped.');
            return true;
          }
        } catch (error) {
          appLog(
            '[BG] iOS execution lease channel unavailable; continuing with '
            'the standard Workmanager task: ${error.runtimeType}',
          );
        }
      }

      try {
        final runResult = await _executeInternal(
          task,
          cancellation: cancellation,
          taskDeadline: taskDeadline,
        );
        final contentOutcome = runResult.contentOutcome;
        if (contentOutcome != null) {
          try {
            await adaptiveBackgroundFetchScheduler
                .recordContentFetchOutcome(contentOutcome);
          } catch (error) {
            appLog(
              '[BG] Failed to persist background cadence outcome: '
              '${error.runtimeType}',
            );
          }
        }
        final contentAnalyticsOutcome = switch (contentOutcome) {
          background_scheduler.BackgroundContentFetchOutcome.newContent =>
            NotificationCheckOutcome.contentFound,
          background_scheduler.BackgroundContentFetchOutcome.emptySuccess =>
            NotificationCheckOutcome.empty,
          background_scheduler.BackgroundContentFetchOutcome.failed =>
            NotificationCheckOutcome.failed,
          null => _notificationShownThisRun
              ? NotificationCheckOutcome.contentFound
              : NotificationCheckOutcome.empty,
        };
        final analyticsOutcome =
            runResult.analyticsOutcome ?? contentAnalyticsOutcome;
        await appAnalytics.logNotificationCheckCompleted(
          executionContext: NotificationExecutionContext.backgroundPeriodic,
          triggerSource: 'workmanager',
          outcome: analyticsOutcome,
          notificationShown: _notificationShownThisRun,
          durationMilliseconds:
              DateTime.now().difference(taskStartedAt).inMilliseconds,
        );
        return runResult.success;
      } on BackgroundNotificationExecutionCancelled {
        await appAnalytics.logNotificationCheckCompleted(
          executionContext: NotificationExecutionContext.backgroundPeriodic,
          triggerSource: 'workmanager',
          outcome: NotificationCheckOutcome.cancelled,
          notificationShown: _notificationShownThisRun,
          durationMilliseconds:
              DateTime.now().difference(taskStartedAt).inMilliseconds,
        );
        return false;
      } finally {
        await releaseExecutionLease();
      }
    }

    final taskFuture = runTask();
    if (!Platform.isIOS) return taskFuture;
    return taskFuture.timeout(
      _iosTaskCompletionTimeout,
      onTimeout: () async {
        appLog(
          '[BG] iOS task reached the 29s completion limit; '
          'cancelling work and completing successfully.',
        );
        cancellation.cancel();
        await releaseExecutionLease();
        await appAnalytics.logNotificationCheckCompleted(
          executionContext: NotificationExecutionContext.backgroundPeriodic,
          triggerSource: 'workmanager',
          outcome: NotificationCheckOutcome.timedOut,
          notificationShown: _notificationShownThisRun,
          durationMilliseconds:
              DateTime.now().difference(taskStartedAt).inMilliseconds,
        );
        return true;
      },
    );
  }

  Future<_BackgroundNotificationRunResult> _executeInternal(
    String task, {
    required BackgroundNotificationExecutionCancellation cancellation,
    required DateTime? taskDeadline,
  }) async {
    appLog("===============================================");
    appLog("BACKGROUND TASK TRIGGERED: $task");
    appLog("Time: ${DateTime.now()}");
    appLog("===============================================");
    final startTime = DateTime.now();
    final deliveryWindow = _NoteDeliveryWindow(taskDeadline);
    bool didFindNewNotificationContent = false;
    bool didCompleteNotesCheck = false;
    bool didCompleteActivitiesCheck = false;
    bool didCompleteUnreadRestoration = false;
    try {
      cancellation.throwIfCancelled();
      final notificationService = NotificationService();
      await notificationService.initForBackgroundDisplay();
      cancellation.throwIfCancelled();
      appLog("[BG] NotificationService initialized");
      SharedPreferences prefs;
      try {
        prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        appLog('[BG] SharedPreferences loaded successfully');
        await FAHttp.initFromPrefs(prefs: prefs);
        cancellation.throwIfCancelled();
        HttpOverrides.global = FreshHttpOverrides();
      } catch (e) {
        cancellation.throwIfCancelled();
        appLog('[BG ERROR] Failed to load SharedPreferences: $e');
        return const _BackgroundNotificationRunResult(
          success: false,
          contentOutcome:
              background_scheduler.BackgroundContentFetchOutcome.failed,
        );
      }
      final bool isAppActive =
          appForegroundStatePreference.isAppForegroundActive(prefs);
      appLog('[BG] App active status: $isAppActive');
      if (isAppActive) {
        appLog('[BG] App is ACTIVE - skipping background fetch');
        appLog(
            '[BG] Task completed (skipped) in ${DateTime.now().difference(startTime).inSeconds}s');
        return const _BackgroundNotificationRunResult(
          success: true,
          analyticsOutcome: NotificationCheckOutcome.skippedAppActive,
        );
      }
      appLog('[BG] App is INACTIVE - proceeding with background fetch');
      if (task == background_scheduler.fetchBackgroundTask ||
          task == background_scheduler.iOSWorkInitTask ||
          task == Workmanager.iOSBackgroundTask) {
        appLog('[BG] Valid background task detected: $task');
        kDebugPrint('[BG] Headless background worker is running.');
        try {
          cancellation.throwIfCancelled();
          final backgroundUpdateInfo = await _loadBackgroundUpdateInfo(
            cancellation,
          );
          cancellation.throwIfCancelled();
          if (backgroundUpdateInfo?.currentVersionAllowed == false) {
            appLog('[BG] Current app version is not allowed - skipping fetch');
            await _showBackgroundUpdateNotificationIfNeeded(
              notificationService,
              prefs,
              cancellation,
              updateInfo: backgroundUpdateInfo,
            );
            return const _BackgroundNotificationRunResult(success: true);
          }
          bool didFirstRunSkip = prefs.getBool('did_first_run_skip') ?? false;
          appLog('[BG] First run skip status: $didFirstRunSkip');
          if (!didFirstRunSkip) {
            appLog('[BG] First run not complete - skipping notifications');
            return const _BackgroundNotificationRunResult(success: true);
          }
          appLog('[BG] === Starting INBOX CHECK ===');
          try {
            bool noteProcessingFailed = false;
            await prefs.reload();
            if (appForegroundStatePreference.isAppForegroundActive(prefs)) {
              return const _BackgroundNotificationRunResult(
                success: true,
                analyticsOutcome: NotificationCheckOutcome.skippedAppActive,
              );
            }
            final Set<String> shownSet = await MessageStorage.getShownNoteIds();
            final Set<String> seenSet = await MessageStorage.getSeenNoteIds();
            cancellation.throwIfCancelled();
            final inboxStopwatch = Stopwatch()..start();
            final BackgroundInboxSnapshot snapshot =
                await fetchBackgroundInboxSnapshot(
              shownNoteIds: shownSet,
              seenNoteIds: seenSet,
              isCancelled: () => cancellation.isCancelled,
            );
            cancellation.throwIfCancelled();
            inboxStopwatch.stop();
            final List<Message> fetchedInbox = snapshot.messages;
            final currentCounts = snapshot.topbarCounts;
            await prefs.reload();
            if (appForegroundStatePreference.isAppForegroundActive(prefs)) {
              return const _BackgroundNotificationRunResult(
                success: true,
                analyticsOutcome: NotificationCheckOutcome.skippedAppActive,
              );
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

            appLog('[BG] === Starting NOTIFICATION COUNTS CHECK ===');
            try {
              final activityResult = await _processActivitySnapshot(
                counts: currentCounts,
                notificationService: notificationService,
                prefs: prefs,
                cancellation: cancellation,
              );
              didCompleteActivitiesCheck = activityResult.completed;
              if (activityResult.foundNewContent) {
                didFindNewNotificationContent = true;
              }
            } on BackgroundNotificationExecutionCancelled {
              rethrow;
            } catch (error) {
              appLog(
                '[BG ERROR] Notification counts check failed: $error',
              );
            }

            await prefs.reload();
            cancellation.throwIfCancelled();
            if (appForegroundStatePreference.isAppForegroundActive(prefs)) {
              return const _BackgroundNotificationRunResult(
                success: true,
                analyticsOutcome: NotificationCheckOutcome.skippedAppActive,
              );
            }

            final List<Message> unread =
                fetchedInbox.where((m) => m.isUnread).toList();
            kDebugPrint('[BG] Found ${unread.length} unread messages');
            final claimedNoteIds = <String>{...shownSet};
            final List<Message> newNotes = unread
                .where((message) => claimedNoteIds.add(message.id))
                .toList();
            if (newNotes.isNotEmpty) {
              didFindNewNotificationContent = true;
            }
            kDebugPrint('[BG] New unread messages: ${newNotes.length}');
            final alerts = newNotes
                .map((message) => _PreparedNoteAlert(message: message))
                .toList(growable: false);

            for (final alert in alerts) {
              cancellation.throwIfCancelled();
              final requestGateWait =
                  FaRequestCoordinator.instance.timeUntilNextRequestSlot;
              if (!deliveryWindow.canFetchFullNote(
                alerts.length,
                requestGateWait: requestGateWait,
              )) {
                appLog(
                  '[BG_NOTE_CONTENT] phase=budget_fallback '
                  'remaining=${alerts.length} '
                  'gateWaitMs=${requestGateWait.inMilliseconds}',
                );
                break;
              }

              final message = alert.message;
              kDebugPrint(
                '[BG] Fetching message content: ${message.id} '
                'from ${message.sender}',
              );
              try {
                await MessageStorage.addPendingUnreadRestore(
                  noteId: message.id,
                  link: message.link,
                );
                appLog(
                  '[BG_NOTE_UNREAD] noteId=${message.id} source=new_note '
                  'phase=pending_persisted',
                );
              } catch (error) {
                appLog(
                  '[BG_NOTE_CONTENT] noteId=${message.id} '
                  'phase=prepare_failed error=${error.runtimeType}',
                );
                break;
              }

              final contentStopwatch = Stopwatch()..start();
              try {
                final fetchedContent = await cancellation.runDioOperation(
                  (cancelToken) => fetchBackgroundNoteContent(
                    message.link,
                    cancelToken: cancelToken,
                  ),
                  finishBy: deliveryWindow.contentFinishBy(alerts.length),
                  timeoutReason: 'Note content budget expired',
                );
                cancellation.throwIfCancelled();
                contentStopwatch.stop();
                final trimmedContent = fetchedContent.trim();
                if (trimmedContent.isNotEmpty) {
                  alert.fullBody = trimmedContent;
                }
                appLog(
                  '[BG_NOTE_CONTENT] noteId=${message.id} success=true '
                  'status=200 durationMs=${contentStopwatch.elapsedMilliseconds} '
                  'bodyLength=${fetchedContent.length}',
                );
                if (trimmedContent.isEmpty) break;
              } catch (error) {
                cancellation.throwIfCancelled();
                contentStopwatch.stop();
                appLog(
                  '[BG_NOTE_CONTENT] noteId=${message.id} success=false '
                  'status=unknown '
                  'durationMs=${contentStopwatch.elapsedMilliseconds} '
                  'error=${error.runtimeType}',
                );
                break;
              }
            }

            try {
              didCompleteUnreadRestoration =
                  await _restorePendingUnreadBatch(
                cancellation: cancellation,
                finishBy: deliveryWindow.unreadFinishBy(alerts.length),
              );
            } on BackgroundNotificationExecutionCancelled {
              rethrow;
            } catch (error) {
              appLog(
                '[BG ERROR] Bulk unread restoration failed: '
                '${error.runtimeType}',
              );
            }

            final allNotesDelivered = await _deliverPreparedNoteAlerts(
              alerts: alerts,
              deliveryWindow: deliveryWindow,
              notificationService: notificationService,
              prefs: prefs,
              cancellation: cancellation,
            );
            if (!allNotesDelivered) {
              noteProcessingFailed = true;
            }

            final fetchedIds =
                fetchedInbox.map((message) => message.id).toList();
            if (fetchedIds.isNotEmpty) {
              cancellation.throwIfCancelled();
              await MessageStorage.addSeenNoteIds(fetchedIds);
              cancellation.throwIfCancelled();
              kDebugPrint('[BG] Saved ${fetchedIds.length} seen message IDs');
            }
            didCompleteNotesCheck = !noteProcessingFailed;
          } on BackgroundNotificationExecutionCancelled {
            rethrow;
          } catch (e) {
            appLog('[BG ERROR] Notes check failed: $e');
          }
          cancellation.throwIfCancelled();
          final didCompleteContentFetch = didCompleteNotesCheck &&
              didCompleteActivitiesCheck &&
              didCompleteUnreadRestoration;
          final contentOutcome = didCompleteContentFetch
              ? didFindNewNotificationContent
                  ? background_scheduler
                      .BackgroundContentFetchOutcome.newContent
                  : background_scheduler
                      .BackgroundContentFetchOutcome.emptySuccess
              : background_scheduler.BackgroundContentFetchOutcome.failed;
          if (deliveryWindow.canShowUpdateNotification) {
            try {
              await _showBackgroundUpdateNotificationIfNeeded(
                notificationService,
                prefs,
                cancellation,
                updateInfo: backgroundUpdateInfo,
              );
            } on BackgroundNotificationExecutionCancelled {
              rethrow;
            }
          }
          appLog('[BG] === Task completed successfully ===');
          appLog(
              '[BG] Total duration: ${DateTime.now().difference(startTime).inSeconds}s');
          return _BackgroundNotificationRunResult(
            success: true,
            contentOutcome: contentOutcome,
          );
        } on BackgroundNotificationExecutionCancelled {
          rethrow;
        } catch (e, stackTrace) {
          appLog('[BG ERROR] Task failed: $e');
          kDebugPrint('[BG ERROR] Stack: $stackTrace');
          await appCrashReporter.recordNonFatal(
            e,
            stackTrace,
            reason: 'background_notification_task_failed',
            executionContext: 'background_periodic',
          );
          if (e.toString().contains('network') ||
              e.toString().contains('timeout') ||
              e.toString().contains('connection') ||
              e.toString().contains('SocketException')) {
            appLog('[BG] Network error detected - will retry');
            return const _BackgroundNotificationRunResult(
              success: false,
              contentOutcome:
                  background_scheduler.BackgroundContentFetchOutcome.failed,
            );
          }
          appLog('[BG] Non-network error - marking as complete');
          return const _BackgroundNotificationRunResult(
            success: true,
            contentOutcome:
                background_scheduler.BackgroundContentFetchOutcome.failed,
          );
        }
      }
      appLog('[BG] Unknown task type: $task');
      return const _BackgroundNotificationRunResult(success: true);
    } on BackgroundNotificationExecutionCancelled {
      rethrow;
    } catch (e) {
      appLog('[BG FATAL ERROR] Callback dispatcher crash: $e');
      return const _BackgroundNotificationRunResult(
        success: false,
        contentOutcome:
            background_scheduler.BackgroundContentFetchOutcome.failed,
      );
    }
  }

  Future<AppUpdateInfo?> _loadBackgroundUpdateInfo(
    BackgroundNotificationExecutionCancellation cancellation,
  ) async {
    final githubCancelToken = CancelToken();
    try {
      cancellation.throwIfCancelled();
      final updateInfo = await fetchLatestAppUpdateInfo(
        forceRefresh: true,
        cancelToken: githubCancelToken,
      ).timeout(
        _backgroundUpdatePreflightTimeout,
        onTimeout: () {
          if (!githubCancelToken.isCancelled) {
            githubCancelToken.cancel('Background update preflight timed out');
          }
          appLog(
            '[BG] GitHub version preflight exceeded 5s; '
            'continuing with the FA fetch.',
          );
          return null;
        },
      );
      cancellation.throwIfCancelled();
      return updateInfo;
    } on BackgroundNotificationExecutionCancelled {
      rethrow;
    } catch (error) {
      cancellation.throwIfCancelled();
      appLog(
        '[BG] GitHub version preflight failed; continuing with the FA fetch: '
        '${error.runtimeType}',
      );
      return null;
    }
  }

  Future<void> _showBackgroundUpdateNotificationIfNeeded(
    NotificationService notificationService,
    SharedPreferences prefs,
    BackgroundNotificationExecutionCancellation cancellation, {
    required AppUpdateInfo? updateInfo,
  }) async {
    try {
      cancellation.throwIfCancelled();
      if (updateInfo == null || !updateInfo.updateAvailable) return;

      final shownKey =
          'shown_update_notification_for_${updateInfo.currentVersion}';
      await prefs.reload();
      cancellation.throwIfCancelled();
      if (prefs.getBool(shownKey) ?? false) return;
      if (appForegroundStatePreference.isAppForegroundActive(prefs)) return;

      await notificationService.showNotification(
        NotificationService.appUpdateNotificationId,
        'New Update Available!',
        'Tap to open FA Notifier.',
        NotificationService.appUpdatePayload,
        'updates',
      );
      _notificationShownThisRun = true;
      await appAnalytics.logNotificationDisplayed(
        executionContext: NotificationExecutionContext.backgroundPeriodic,
        notificationType: 'update',
      );
      cancellation.throwIfCancelled();
      await prefs.setBool(shownKey, true);
      appLog(
        '[BG] Update notification shown for installed version '
        '${updateInfo.currentVersion}; latest version ${updateInfo.latestVersion}',
      );
    } on BackgroundNotificationExecutionCancelled {
      rethrow;
    } catch (e, st) {
      appLog('[BG ERROR] Update notification check failed: $e');
      kDebugPrint('[BG ERROR] Update notification stack: $st');
    }
  }
}
