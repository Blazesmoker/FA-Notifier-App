import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/features/notifications/domain/notification_counts.dart';
import 'package:FANotifier/features/notes/data/notes_refresh_service.dart';
import 'package:FANotifier/features/notifications/data/activities_notification_state.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_service.dart';
import 'package:FANotifier/features/notifications/data/notification_refresh_service.dart';
import 'package:FANotifier/features/notifications/data/notification_service.dart';

class FaActivitiesPollingService with WidgetsBindingObserver {
  static final FaActivitiesPollingService _i =
      FaActivitiesPollingService._internal();
  factory FaActivitiesPollingService() => _i;
  FaActivitiesPollingService._internal();

  static const Duration _interval = Duration(seconds: 180);

  FANotificationService? _faNotificationService;
  Timer? _timer;
  Future<void>? _inFlight;
  StreamSubscription<void>? _refreshSub;
  AppLifecycleState? _lastLifecycleState;
  bool _observerAttached = false;
  bool _notesScreenVisible = false;
  bool _submissionsScreenVisible = false;
  bool _notificationsScreenVisible = false;
  bool _foregroundEntryCheckPending = true;
  String? _activeNotificationSectionTitle;
  NotificationCounts? _pendingExternalCounts;
  bool _pendingExternalResetTimer = false;
  String? _pendingExternalSource;
  bool _pendingStartTrigger = false;
  bool _pendingStartResetTimer = false;
  String? _pendingStartSource;
  bool _pendingResumeActivityNotification = false;

  bool get _acknowledgingScreenVisible =>
      _notesScreenVisible ||
      _submissionsScreenVisible ||
      _notificationsActiveSectionAcknowledgesAny;

  bool get _notificationsActiveSectionAcknowledgesAny =>
      _acknowledgeWatchesVisible ||
      _acknowledgeCommentsVisible ||
      _acknowledgeFavoritesVisible ||
      _acknowledgeJournalsVisible;

  String get _activeNotificationSectionLower =>
      _activeNotificationSectionTitle?.toLowerCase() ?? '';

  bool get _acknowledgeWatchesVisible =>
      _notificationsScreenVisible &&
      _activeNotificationSectionLower.contains('watch');

  bool get _acknowledgeCommentsVisible =>
      _notificationsScreenVisible &&
      _activeNotificationSectionLower.contains('comment');

  bool get _acknowledgeFavoritesVisible =>
      _notificationsScreenVisible &&
      _activeNotificationSectionLower.contains('favorite');

  bool get _acknowledgeJournalsVisible =>
      _notificationsScreenVisible &&
      _activeNotificationSectionLower.contains('journal') &&
      !_activeNotificationSectionLower.contains('comment');

  void start({required FANotificationService faNotificationService}) {
    _faNotificationService = faNotificationService;
    if (!_observerAttached) {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    }
    _refreshSub ??= NotificationRefreshService().onRefresh.listen((_) {
      triggerNow(resetTimer: true, source: 'notification_refresh_service');
    });
    _ensureTimer();
    if (_pendingStartTrigger) {
      final resetTimer = _pendingStartResetTimer;
      final source = _pendingStartSource ?? 'pending_start';
      _pendingStartTrigger = false;
      _pendingStartResetTimer = false;
      _pendingStartSource = null;
      unawaited(triggerNow(resetTimer: resetTimer, source: source));
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _inFlight = null;
    _refreshSub?.cancel();
    _refreshSub = null;
    _faNotificationService = null;
    _pendingExternalCounts = null;
    _pendingExternalResetTimer = false;
    _pendingExternalSource = null;
    _pendingStartTrigger = false;
    _pendingStartResetTimer = false;
    _pendingStartSource = null;
    _pendingResumeActivityNotification = false;
    _foregroundEntryCheckPending = true;
    _notesScreenVisible = false;
    _submissionsScreenVisible = false;
    _notificationsScreenVisible = false;
    _activeNotificationSectionTitle = null;
    if (_observerAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
  }

  void resetSchedule() {
    if (_faNotificationService == null) return;
    _resetTimer();
  }

  void setNotesScreenVisible(bool visible) {
    if (_notesScreenVisible == visible) return;
    _notesScreenVisible = visible;
    if (visible) {
      _acknowledgeCurrentVisibleCountsWithoutFetch();
    }
  }

  void setSubmissionsScreenVisible(bool visible) {
    if (_submissionsScreenVisible == visible) return;
    _submissionsScreenVisible = visible;
    if (visible) {
      _acknowledgeCurrentVisibleCountsWithoutFetch();
    }
  }

  void setNotificationsScreenVisible(
    bool visible, {
    String? activeSectionTitle,
  }) {
    if (_notificationsScreenVisible == visible &&
        (activeSectionTitle == null ||
            _activeNotificationSectionTitle == activeSectionTitle)) {
      return;
    }
    final wasVisible = _acknowledgingScreenVisible;
    _notificationsScreenVisible = visible;
    if (!visible) {
      _activeNotificationSectionTitle = null;
    } else if (activeSectionTitle != null) {
      _activeNotificationSectionTitle = activeSectionTitle;
    }
    _handleAcknowledgingScreenVisibilityChange(wasVisible);
  }

  void setNotificationsScreenActiveSection(String? sectionTitle) {
    if (_activeNotificationSectionTitle == sectionTitle) return;
    final wasVisible = _acknowledgingScreenVisible;
    _activeNotificationSectionTitle = sectionTitle;
    _handleAcknowledgingScreenVisibilityChange(wasVisible);
  }

  void _handleAcknowledgingScreenVisibilityChange(bool wasVisible) {
    if (wasVisible || !_acknowledgingScreenVisible) return;

    final source = _foregroundEntryCheckPending
        ? 'foreground_entry_visible'
        : 'acknowledging_screen_visible';
    final existing = _inFlight;
    if (existing == null) {
      unawaited(triggerNow(
        resetTimer: true,
        source: source,
      ));
      return;
    }

    unawaited(existing.whenComplete(() async {
      if (!_acknowledgingScreenVisible) return;
      await triggerNow(
        resetTimer: true,
        source: _foregroundEntryCheckPending
            ? 'foreground_entry_visible'
            : 'acknowledging_screen_visible',
      );
    }));
  }

  void _acknowledgeCurrentVisibleCountsWithoutFetch() {
    final svc = _faNotificationService;
    if (svc == null || !svc.hasValidLatestCountsSnapshot) return;
    unawaited(_acknowledgeVisibleCounts(
      ActivitiesNotificationStateStore(),
      svc.latestCounts,
    ));
  }

  bool _isForegroundEntrySource(String source) {
    return source == 'startup_warmup' ||
        source == 'lifecycle_resumed' ||
        source == 'foreground_entry_visible' ||
        source == 'login_established';
  }

  Future<void> _acknowledgeVisibleCounts(
    ActivitiesNotificationStateStore activitiesStateStore,
    NotificationCounts currentCounts,
  ) {
    return activitiesStateStore.acknowledgeVisibleCounts(
      currentCounts: currentCounts,
      acknowledgeSubmissions: _submissionsScreenVisible,
      acknowledgeWatches: _acknowledgeWatchesVisible,
      acknowledgeComments: _acknowledgeCommentsVisible,
      acknowledgeFavorites: _acknowledgeFavoritesVisible,
      acknowledgeJournals: _acknowledgeJournalsVisible,
      acknowledgeNotes: _notesScreenVisible,
    );
  }

  Future<void> triggerNow({required bool resetTimer, required String source}) {
    if (resetTimer) {
      _resetTimer();
    }
    final existing = _inFlight;
    if (existing != null) return existing;

    final svc = _faNotificationService;
    if (svc == null) {
      _pendingStartTrigger = true;
      _pendingStartResetTimer = _pendingStartResetTimer || resetTimer;
      _pendingStartSource = source;
      return Future.value();
    }

    final future = _runOnce(svc, source: source).whenComplete(() {
      _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  Future<void> _drainPendingExternalCountsAfter(Future<void> existing) async {
    try {
      await existing;
    } catch (_) {}
    final pendingCounts = _pendingExternalCounts;
    final pendingSource = _pendingExternalSource;
    if (pendingCounts == null || pendingSource == null) return;

    final resetTimer = _pendingExternalResetTimer;
    _pendingExternalCounts = null;
    _pendingExternalResetTimer = false;
    _pendingExternalSource = null;

    await handleExternalCounts(
      currentCounts: pendingCounts,
      resetTimer: resetTimer,
      source: pendingSource,
    );
  }

  Future<void> handleExternalCounts({
    required NotificationCounts currentCounts,
    required bool resetTimer,
    required String source,
  }) {
    if (resetTimer) {
      _resetTimer();
    }
    final existing = _inFlight;
    if (existing != null) {
      _faNotificationService?.applyTopbarCounts(currentCounts);
      _pendingExternalCounts = currentCounts;
      _pendingExternalResetTimer = _pendingExternalResetTimer || resetTimer;
      _pendingExternalSource = source;
      return _drainPendingExternalCountsAfter(existing);
    }

    _faNotificationService?.applyTopbarCounts(currentCounts);

    final future = _maybeSendActivitiesNotification(
      currentCounts,
      triggerNotesRefreshOnNotesIncrease: false,
      source: source,
    ).whenComplete(() {
      _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  Future<void> _runOnce(FANotificationService svc,
      {required String source}) async {
    try {
      await svc.fetchNotifications();
    } catch (_) {
      return;
    }
    if (svc.errorMessage != null || !svc.hasValidLatestCountsSnapshot) return;
    await _maybeSendActivitiesNotification(svc.latestCounts, source: source);
  }

  void _ensureTimer() {
    if (_faNotificationService == null) return;
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) {
      triggerNow(resetTimer: false, source: 'timer');
    });
  }

  void _resetTimer() {
    if (_faNotificationService == null) return;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      triggerNow(resetTimer: false, source: 'timer');
    });
  }

  String _formatNotificationPart({
    required int current,
    required int increasedBy,
    required String suffix,
  }) {
    if (current <= 0) return '';
    if (increasedBy > 0) {
      return '$current$suffix(+$increasedBy)';
    }
    return '$current$suffix';
  }

  String _buildNotificationMessage(
    NotificationCounts counts,
    NotificationCounts increases,
  ) {
    final parts = <String>[];
    final submissions = _formatNotificationPart(
      current: counts.submissions,
      increasedBy: increases.submissions,
      suffix: 'S',
    );
    if (submissions.isNotEmpty) parts.add(submissions);
    final watches = _formatNotificationPart(
      current: counts.watches,
      increasedBy: increases.watches,
      suffix: 'W',
    );
    if (watches.isNotEmpty) parts.add(watches);
    final comments = _formatNotificationPart(
      current: counts.comments,
      increasedBy: increases.comments,
      suffix: 'C',
    );
    if (comments.isNotEmpty) parts.add(comments);
    final favorites = _formatNotificationPart(
      current: counts.favorites,
      increasedBy: increases.favorites,
      suffix: 'F',
    );
    if (favorites.isNotEmpty) parts.add(favorites);
    final journals = _formatNotificationPart(
      current: counts.journals,
      increasedBy: increases.journals,
      suffix: 'J',
    );
    if (journals.isNotEmpty) parts.add(journals);
    final notes = _formatNotificationPart(
      current: counts.notes,
      increasedBy: increases.notes,
      suffix: 'N',
    );
    if (notes.isNotEmpty) parts.add(notes);
    return parts.join(' | ');
  }

  Future<void> _maybeSendActivitiesNotification(
    NotificationCounts currentCounts, {
    bool triggerNotesRefreshOnNotesIncrease = true,
    required String source,
  }) async {
    final activitiesStateStore = ActivitiesNotificationStateStore();
    final foregroundEntryCheck =
        _foregroundEntryCheckPending || _isForegroundEntrySource(source);
    var deferredForResume = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

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

      if (!foregroundEntryCheck) {
        await _acknowledgeVisibleCounts(
          activitiesStateStore,
          currentCounts,
        );
      }
      final ActivitiesDiff diff = await activitiesStateStore
          .diffFromAcknowledged(currentCounts: currentCounts);

      if (triggerNotesRefreshOnNotesIncrease && diff.increasedBy.notes > 0) {
        NotesRefreshService().triggerRefresh();
      }

      final bool acknowledgeRequested =
          await activitiesStateStore.consumeAcknowledgeOnNextForegroundFetch();
      if (acknowledgeRequested) {
        await activitiesStateStore.acknowledgeCurrentCounts(
          currentCounts: currentCounts,
        );
        await NotificationService().cancelActivityNotification();
        return;
      }

      final NotificationCounts enabledIncreases = NotificationCounts(
        submissions: submissionsEnabled ? diff.increasedBy.submissions : 0,
        watches: watchesEnabled ? diff.increasedBy.watches : 0,
        comments: commentsEnabled ? diff.increasedBy.comments : 0,
        favorites: favoritesEnabled ? diff.increasedBy.favorites : 0,
        journals: journalsEnabled ? diff.increasedBy.journals : 0,
        notes: notesEnabled ? diff.increasedBy.notes : 0,
      );

      final bool hasEnabledIncrease = enabledIncreases.submissions > 0 ||
          enabledIncreases.watches > 0 ||
          enabledIncreases.comments > 0 ||
          enabledIncreases.favorites > 0 ||
          enabledIncreases.journals > 0 ||
          enabledIncreases.notes > 0;
      if (!hasEnabledIncrease) {
        return;
      }

      final bool soundActivitiesEnabled =
          prefs.getBool('sound_new_activities_enabled') ?? true;
      final bool vibrationActivitiesEnabled =
          prefs.getBool('vibration_new_activities_enabled') ?? true;
      if (!soundActivitiesEnabled && !vibrationActivitiesEnabled) {
        return;
      }

      final NotificationCounts filteredCounts = NotificationCounts(
        submissions: submissionsEnabled ? currentCounts.submissions : 0,
        watches: watchesEnabled ? currentCounts.watches : 0,
        comments: commentsEnabled ? currentCounts.comments : 0,
        favorites: favoritesEnabled ? currentCounts.favorites : 0,
        journals: journalsEnabled ? currentCounts.journals : 0,
        notes: notesEnabled ? currentCounts.notes : 0,
      );
      final String messageBody = _buildNotificationMessage(
        filteredCounts,
        enabledIncreases,
      );
      if (!messageBody.contains('(+')) return;

      final bool isDuplicate =
          await activitiesStateStore.areCurrentCountsLastShown(
        currentCounts: currentCounts,
      );
      if (isDuplicate) return;

      if (Platform.isIOS &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await activitiesStateStore.deferActivityNotification(
          currentCounts: currentCounts,
          body: messageBody,
        );
        _pendingResumeActivityNotification = true;
        deferredForResume = true;
        debugPrint(
          '[ACTIVITY_NOTIF] producer=foreground_polling deferred '
          'lifecycle=${WidgetsBinding.instance.lifecycleState} body=$messageBody',
        );
        return;
      }

      if (Platform.isIOS) {
        debugPrint(
          '[ACTIVITY_NOTIF] producer=foreground_polling badge=unchanged '
          'lifecycle=${WidgetsBinding.instance.lifecycleState}',
        );
      }
      final notificationService = NotificationService();
      if (Platform.isIOS) {
        await notificationService.cancelActivityNotification();
      }
      await notificationService.showNotification(
        NotificationService.activityNotificationId,
        'New FA Activity',
        messageBody,
        'activity_fa_activity',
        'activities',
      );
      await activitiesStateStore.markActivityNotificationShown(
        currentCounts: currentCounts,
        body: messageBody,
      );
      _pendingResumeActivityNotification = false;
      debugPrint(
        '[ACTIVITY_NOTIF] producer=foreground_polling shown body=$messageBody',
      );
    } catch (_) {
    } finally {
      if (foregroundEntryCheck && !deferredForResume) {
        try {
          await _acknowledgeVisibleCounts(
            activitiesStateStore,
            currentCounts,
          );
        } catch (_) {}
        _foregroundEntryCheckPending = false;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final prev = _lastLifecycleState;
    _lastLifecycleState = state;

    if (state == AppLifecycleState.resumed) {
      final bool realResume = prev == AppLifecycleState.paused ||
          prev == AppLifecycleState.hidden ||
          prev == AppLifecycleState.detached;
      _ensureTimer();
      if (realResume || _pendingResumeActivityNotification) {
        _foregroundEntryCheckPending = true;
        _pendingResumeActivityNotification = false;
        final existing = _inFlight;
        if (existing == null) {
          triggerNow(resetTimer: true, source: 'lifecycle_resumed');
        } else {
          unawaited(existing.whenComplete(() async {
            if (_lastLifecycleState != AppLifecycleState.resumed) return;
            await triggerNow(resetTimer: true, source: 'lifecycle_resumed');
          }));
        }
      }
      return;
    }

    if ((Platform.isIOS && state == AppLifecycleState.inactive) ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
      return;
    }
  }
}
