import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/notifications/domain/activity_count_change_policy.dart';
import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/shared/fa/domain/fa_notification_state_port.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';
import 'package:fanotifier/features/notes/data/notes_refresh_service.dart';
import 'package:fanotifier/features/notes/data/manual_note_activity_store.dart';
import 'package:fanotifier/features/notes/domain/note_activity_snapshot.dart';
import 'package:fanotifier/features/notifications/data/activities_notification_state.dart';
import 'package:fanotifier/features/notifications/domain/notification_payloads.dart';
import 'package:fanotifier/features/notifications/data/notification_refresh_service.dart';
import 'package:fanotifier/features/notifications/data/notification_badge_state.dart'
    as notification_badge;
import 'package:fanotifier/features/notifications/data/notification_service.dart';
import 'package:fanotifier/core/analytics/app_analytics.dart';
import 'package:fanotifier/core/network/fa_page_counter_observer.dart';
import 'package:fanotifier/shared/fa/domain/fa_page_counter_observation.dart';
import 'package:fanotifier/features/notes/domain/notes_repository.dart';
import 'package:fanotifier/features/notes/domain/notes_inbox_snapshot.dart';
import 'package:fanotifier/features/notes/domain/inbox_second_page_policy.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';

class FaActivitiesPollingService
    with WidgetsBindingObserver
    implements FaActivitiesPollingPort {
  static final FaActivitiesPollingService _i =
      FaActivitiesPollingService._internal();
  factory FaActivitiesPollingService() => _i;
  FaActivitiesPollingService._internal();

  static const Duration _interval = Duration(minutes: 4);
  static const ActivityCountChangePolicy _countChangePolicy =
      ActivityCountChangePolicy();

  FaNotificationStatePort? _faNotificationService;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _inFlightIncludesNotificationFetch = false;
  StreamSubscription<void>? _refreshSub;
  AppLifecycleState? _lastLifecycleState;
  bool _observerAttached = false;
  bool _notesScreenVisible = false;
  bool _submissionsScreenVisible = false;
  bool _notificationsScreenVisible = false;
  bool _foregroundEntryCheckPending = true;
  String? _activeNotificationSectionTitle;
  NotificationCounts? _pendingExternalCounts;
  NoteActivitySnapshot? _pendingExternalNoteActivitySnapshot;
  bool _pendingExternalResetTimer = false;
  String? _pendingExternalSource;
  int? _pendingExternalStartedAt;
  bool _pendingStartTrigger = false;
  bool _pendingStartResetTimer = false;
  String? _pendingStartSource;
  bool _pendingResumeActivityNotification = false;
  bool _pendingNotesEntryAcknowledgement = false;
  bool _notificationShownInCurrentRun = false;
  NotesRepository? _notesRepository;
  Future<void> _noteTrackingReady = Future<void>.value();
  StreamSubscription<FaPageCounterObservation>? _counterSubscription;
  int _counterSessionGeneration = 0;
  int _lastCounterStartedAt = 0;
  NotificationCounts? _observedCounts;
  int _nextNotificationsAt = 0;
  int _nextInboxAt = 0;
  int _notificationsRetryAt = 0;
  int _inboxRetryAt = 0;
  bool _pendingInboxIncrease = false;
  Future<void>? _ensureNotificationsInFlight;

  bool get _acknowledgingScreenVisible =>
      _submissionsScreenVisible ||
      _notificationsActiveSectionAcknowledgesAny;

  bool get _isResumed =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

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

  @override
  void start({
    required FaNotificationStatePort faNotificationService,
    required NotesRepositoryFactory notesRepositoryFactory,
  }) {
    _faNotificationService = faNotificationService;
    _notesRepository ??= notesRepositoryFactory();
    final notesRepository = _notesRepository;
    _noteTrackingReady = ManualNoteActivityStore().ensureTracking(
      isCancelled: () => !identical(notesRepository, _notesRepository),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_nextNotificationsAt == 0) {
      _nextNotificationsAt = now + _interval.inMilliseconds;
    }
    if (_nextInboxAt == 0) {
      _nextInboxAt = now + _interval.inMilliseconds;
    }
    _counterSessionGeneration = FaPageCounterObserver.instance.start();
    _counterSubscription ??= FaPageCounterObserver.instance.observations.listen(
      _handlePageCounters,
    );
    if (!_observerAttached) {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    }
    _refreshSub ??= NotificationRefreshService().onRefresh.listen((_) {
      triggerNow(
        resetTimer: true,
        source: 'notification_refresh_service',
        requireFresh: true,
      );
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

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    FaPageCounterObserver.instance.stop();
    _counterSubscription?.cancel();
    _counterSubscription = null;
    _notesRepository = null;
    NotesRefreshService().clearInboxSnapshot();
    _observedCounts = null;
    _lastCounterStartedAt = 0;
    _nextNotificationsAt = 0;
    _nextInboxAt = 0;
    _notificationsRetryAt = 0;
    _inboxRetryAt = 0;
    _pendingInboxIncrease = false;
    _ensureNotificationsInFlight = null;
    _inFlight = null;
    _inFlightIncludesNotificationFetch = false;
    _refreshSub?.cancel();
    _refreshSub = null;
    _faNotificationService = null;
    _pendingExternalCounts = null;
    _pendingExternalNoteActivitySnapshot = null;
    _pendingExternalResetTimer = false;
    _pendingExternalSource = null;
    _pendingExternalStartedAt = null;
    _pendingStartTrigger = false;
    _pendingStartResetTimer = false;
    _pendingStartSource = null;
    _pendingResumeActivityNotification = false;
    _pendingNotesEntryAcknowledgement = false;
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

  @override
  void resetSchedule() {
    if (_faNotificationService == null) return;
    _ensureTimer();
  }

  @override
  void setNotesScreenVisible(bool visible) {
    if (_notesScreenVisible == visible) return;
    _notesScreenVisible = visible;
    if (!visible) {
      _pendingNotesEntryAcknowledgement = false;
      return;
    }
    _beginNotesEntryAcknowledgement();
  }

  void _beginNotesEntryAcknowledgement() {
    if (!_notesScreenVisible || !_isResumed) return;
    final svc = _faNotificationService;
    if (svc != null && svc.hasValidLatestCountsSnapshot) {
      _pendingNotesEntryAcknowledgement = false;
      unawaited(
        ActivitiesNotificationStateStore().acknowledgeVisibleCounts(
          currentCounts: svc.latestCounts,
          acknowledgeNotes: true,
        ),
      );
      return;
    }

    _pendingNotesEntryAcknowledgement = true;
    unawaited(_refreshAndAcknowledgeNotesEntry());
  }

  Future<void> _refreshAndAcknowledgeNotesEntry() async {
    await triggerNow(
      resetTimer: true,
      source: 'notes_entry_baseline',
    );
    final svc = _faNotificationService;
    if (!_pendingNotesEntryAcknowledgement ||
        !_notesScreenVisible ||
        !_isResumed ||
        svc == null ||
        svc.errorMessage != null ||
        !svc.hasValidLatestCountsSnapshot) {
      return;
    }
    await ActivitiesNotificationStateStore().acknowledgeVisibleCounts(
      currentCounts: svc.latestCounts,
      acknowledgeNotes: true,
    );
    _pendingNotesEntryAcknowledgement = false;
  }

  @override
  void setSubmissionsScreenVisible(bool visible) {
    if (_submissionsScreenVisible == visible) return;
    _submissionsScreenVisible = visible;
    if (visible) {
      _acknowledgeCurrentVisibleCountsWithoutFetch();
    }
  }

  @override
  void setNotificationsScreenVisible(
    bool visible, {
    String? activeSectionTitle,
  }) {
    if (_notificationsScreenVisible == visible &&
        (activeSectionTitle == null ||
            _activeNotificationSectionTitle == activeSectionTitle)) {
      return;
    }
    final becameVisible = visible && !_notificationsScreenVisible;
    final wasVisible = _acknowledgingScreenVisible;
    _notificationsScreenVisible = visible;
    if (!visible) {
      _activeNotificationSectionTitle = null;
    } else if (activeSectionTitle != null) {
      _activeNotificationSectionTitle = activeSectionTitle;
    }
    _handleAcknowledgingScreenVisibilityChange(wasVisible);
    if (becameVisible && _isResumed) {
      unawaited(ensureNotificationsFresh(source: 'notifications_visible'));
    }
    _scheduleTimer();
  }

  @override
  void setNotificationsScreenActiveSection(String? sectionTitle) {
    if (_activeNotificationSectionTitle == sectionTitle) return;
    final wasVisible = _acknowledgingScreenVisible;
    _activeNotificationSectionTitle = sectionTitle;
    _handleAcknowledgingScreenVisibilityChange(wasVisible);
  }

  void _handleAcknowledgingScreenVisibilityChange(bool wasVisible) {
    if (wasVisible || !_acknowledgingScreenVisible || !_isResumed) return;

    final source = _foregroundEntryCheckPending
        ? 'foreground_entry_visible'
        : 'acknowledging_screen_visible';
    unawaited(_refreshAndAcknowledgeVisibleCounts(source));
  }

  Future<void> _refreshAndAcknowledgeVisibleCounts(String source) async {
    await ensureNotificationsFresh(source: source);
    _acknowledgeCurrentVisibleCountsWithoutFetch();
  }

  void _acknowledgeCurrentVisibleCountsWithoutFetch() {
    final svc = _faNotificationService;
    if (!_isResumed ||
        svc == null ||
        svc.errorMessage != null ||
        !svc.hasValidLatestCountsSnapshot) {
      return;
    }
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
    if (!_isResumed) return Future<void>.value();
    return activitiesStateStore.acknowledgeVisibleCounts(
      currentCounts: currentCounts,
      acknowledgeSubmissions: _submissionsScreenVisible,
      acknowledgeWatches: _acknowledgeWatchesVisible,
      acknowledgeComments: _acknowledgeCommentsVisible,
      acknowledgeFavorites: _acknowledgeFavoritesVisible,
      acknowledgeJournals: _acknowledgeJournalsVisible,
    );
  }

  @override
  Future<void> triggerNow({
    required bool resetTimer,
    required String source,
    bool requireFresh = false,
  }) {
    if (resetTimer) {
      _resetTimer();
    }
    final svc = _faNotificationService;
    if (svc == null) {
      _pendingStartTrigger = true;
      _pendingStartResetTimer = _pendingStartResetTimer || resetTimer;
      _pendingStartSource = source;
      return Future.value();
    }

    final existing = _inFlight;
    if (existing != null) {
      if (_inFlightIncludesNotificationFetch && !requireFresh) {
        return existing;
      }
      return _triggerAfterCurrentRun(existing, svc, source: source);
    }

    _inFlightIncludesNotificationFetch = true;
    late final Future<void> future;
    future = Future<void>.microtask(
      () => _runOnce(svc, source: source),
    ).whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _inFlightIncludesNotificationFetch = false;
        _scheduleTimer();
      }
    });
    _inFlight = future;
    return future;
  }

  bool _listCountsDiffer(NotificationCounts a, NotificationCounts b) {
    return a.watches != b.watches || a.comments != b.comments ||
        a.favorites != b.favorites || a.journals != b.journals;
  }

  bool get _notificationsNeedRefresh {
    final svc = _faNotificationService;
    final fetchedAt = svc?.listFetchedAtMilliseconds;
    final listCounts = svc?.listCounts;
    final observed = _observedCounts;
    return svc == null || svc.errorMessage != null || fetchedAt == null || listCounts == null ||
        DateTime.now().millisecondsSinceEpoch - fetchedAt >= _interval.inMilliseconds ||
        (observed != null && _listCountsDiffer(listCounts, observed));
  }

  @override
  Future<void> ensureNotificationsFresh({required String source}) {
    if (!_isResumed || _faNotificationService == null) {
      return Future<void>.value();
    }
    final existing = _ensureNotificationsInFlight;
    if (existing != null) {
      return existing;
    }
    final service = _faNotificationService;
    final generation = _counterSessionGeneration;
    late final Future<void> operation;
    operation = Future<void>.microtask(() async {
      if (!identical(service, _faNotificationService) ||
          generation != _counterSessionGeneration || !_isResumed) {
        return;
      }
      if (!_notificationsNeedRefresh) {
        return;
      }
      await triggerNow(resetTimer: false, source: source);
      if (!identical(service, _faNotificationService) ||
          generation != _counterSessionGeneration) {
        return;
      }
      final svc = _faNotificationService;
      final observed = _observedCounts;
      if (_isResumed && svc?.errorMessage == null && svc?.listCounts != null &&
          observed != null && _listCountsDiffer(svc!.listCounts!, observed)) {
        await triggerNow(resetTimer: false, source: source);
      }
    }).whenComplete(() {
      if (identical(_ensureNotificationsInFlight, operation)) {
        _ensureNotificationsInFlight = null;
      }
    });
    _ensureNotificationsInFlight = operation;
    return operation;
  }

  void _handlePageCounters(FaPageCounterObservation observation) {
    if (!_isResumed || _faNotificationService == null ||
        observation.sessionGeneration != _counterSessionGeneration ||
        observation.startedAtMilliseconds < _lastCounterStartedAt) {
      return;
    }
    unawaited(handleExternalCounts(
      currentCounts: observation.counts,
      resetTimer: true,
      source: 'native_page_counters',
      startedAtMilliseconds: observation.startedAtMilliseconds,
    ));
  }

  bool _acceptCounts(NotificationCounts counts, int startedAt) {
    if (startedAt < _lastCounterStartedAt) {
      return false;
    }
    final previous = _observedCounts;
    if (previous != null && counts.notes > previous.notes) {
      _pendingInboxIncrease = true;
      _inboxRetryAt = 0;
    }
    _lastCounterStartedAt = startedAt;
    _observedCounts = counts;
    _faNotificationService?.applyTopbarCounts(counts);
    return true;
  }

  Future<void> _triggerAfterCurrentRun(
    Future<void> existing,
    FaNotificationStatePort svc, {
    required String source,
  }) async {
    final generation = _counterSessionGeneration;
    try {
      await existing;
    } catch (_) {}
    if (!identical(_faNotificationService, svc) ||
        generation != _counterSessionGeneration || !_isResumed) {
      return;
    }
    if (_isForegroundEntrySource(source)) {
      _foregroundEntryCheckPending = true;
    }
    await triggerNow(resetTimer: false, source: source);
  }

  Future<void> _drainPendingExternalCountsAfter(Future<void> existing) async {
    try {
      await existing;
    } catch (_) {}
    final pendingCounts = _pendingExternalCounts;
    final pendingSource = _pendingExternalSource;
    if (pendingCounts == null || pendingSource == null) return;

    final resetTimer = _pendingExternalResetTimer;
    final noteActivitySnapshot = _pendingExternalNoteActivitySnapshot;
    final startedAt = _pendingExternalStartedAt;
    _pendingExternalCounts = null;
    _pendingExternalNoteActivitySnapshot = null;
    _pendingExternalResetTimer = false;
    _pendingExternalSource = null;
    _pendingExternalStartedAt = null;

    await handleExternalCounts(
      currentCounts: pendingCounts,
      resetTimer: resetTimer,
      source: pendingSource,
      noteActivitySnapshot: noteActivitySnapshot,
      startedAtMilliseconds: startedAt,
    );
  }

  @override
  Future<void> handleExternalCounts({
    required NotificationCounts currentCounts,
    required bool resetTimer,
    required String source,
    NoteActivitySnapshot? noteActivitySnapshot,
    int? startedAtMilliseconds,
  }) {
    if (_faNotificationService == null || !_isResumed) {
      return Future<void>.value();
    }
    var startedAt = startedAtMilliseconds ??
        noteActivitySnapshot?.startedAtMilliseconds ??
        DateTime.now().millisecondsSinceEpoch;
    if (!_acceptCounts(currentCounts, startedAt)) {
      if (noteActivitySnapshot == null) {
        return Future<void>.value();
      }
      currentCounts = _observedCounts ?? currentCounts;
      startedAt = _lastCounterStartedAt;
      resetTimer = false;
    }
    if (noteActivitySnapshot != null) {
      _rememberInboxCheck(noteActivitySnapshot);
      _pendingInboxIncrease = currentCounts.notes > noteActivitySnapshot.unreadCount &&
          startedAt > noteActivitySnapshot.startedAtMilliseconds;
    }
    if (resetTimer) {
      _nextNotificationsAt = startedAt + _interval.inMilliseconds;
    }
    final existing = _inFlight;
    if (existing != null) {
      _pendingExternalCounts = currentCounts;
      if (noteActivitySnapshot != null) {
        _pendingExternalNoteActivitySnapshot = noteActivitySnapshot;
      }
      _pendingExternalStartedAt = startedAt;
      _pendingExternalResetTimer = _pendingExternalResetTimer || resetTimer;
      _pendingExternalSource = source;
      unawaited(_drainPendingExternalCountsAfter(existing));
      return Future<void>.value();
    }
    final svc = _faNotificationService;
    final generation = _counterSessionGeneration;
    _inFlightIncludesNotificationFetch = false;
    late final Future<void> future;
    future = Future<void>.microtask(() async {
      if (!identical(_faNotificationService, svc) ||
           generation != _counterSessionGeneration) {
        return;
      }
      await _runExternalCountsCheck(
        currentCounts: currentCounts,
        source: source,
        noteActivitySnapshot: noteActivitySnapshot,
      );
    }).whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _scheduleTimer();
      }
    });
    _inFlight = future;
    return future;
  }

  Future<void> _runExternalCountsCheck({
    required NotificationCounts currentCounts,
    required String source,
    NoteActivitySnapshot? noteActivitySnapshot,
  }) async {
    final svc = _faNotificationService;
    final generation = _counterSessionGeneration;
    final stopwatch = Stopwatch()..start();
    _notificationShownInCurrentRun = false;
    await _noteTrackingReady;
    if (generation != _counterSessionGeneration ||
        !identical(_faNotificationService, svc) || !_isResumed) {
      return;
    }
    if (_pendingInboxIncrease && DateTime.now().millisecondsSinceEpoch >= _inboxRetryAt) {
      noteActivitySnapshot = await _refreshInbox();
    }
    if (!identical(_faNotificationService, svc) ||
        generation != _counterSessionGeneration || !_isResumed) {
      return;
    }
    await _maybeSendActivitiesNotification(
      _observedCounts ?? currentCounts,
      source: source,
      existingNoteActivitySnapshot: noteActivitySnapshot,
    );
    if (_notificationsScreenVisible && _notificationsNeedRefresh) {
      unawaited(ensureNotificationsFresh(source: 'notifications_visible_counts'));
    }
    await appAnalytics.logNotificationCheckCompleted(
      executionContext: appAnalytics.foregroundContext(source),
      triggerSource: source,
      outcome: _notificationShownInCurrentRun
          ? NotificationCheckOutcome.contentFound
          : NotificationCheckOutcome.empty,
      notificationShown: _notificationShownInCurrentRun,
      durationMilliseconds: stopwatch.elapsedMilliseconds,
    );
  }

  void _rememberInboxCheck(NoteActivitySnapshot snapshot) {
    final completedAt = snapshot.completedAtMilliseconds ??
        snapshot.startedAtMilliseconds;
    _nextInboxAt = completedAt + _interval.inMilliseconds;
    _inboxRetryAt = 0;
  }

  Future<NoteActivitySnapshot?> _refreshInbox() async {
    final svc = _faNotificationService;
    final generation = _counterSessionGeneration;
    try {
      final snapshot = await NotesRefreshService().refreshInbox(_loadInbox);
      if (!identical(_faNotificationService, svc) ||
          generation != _counterSessionGeneration) {
        return null;
      }
      if (snapshot == null || snapshot.page.topbarCounts == null) {
        _inboxRetryAt = DateTime.now().millisecondsSinceEpoch + _interval.inMilliseconds;
        return null;
      }
      _rememberInboxCheck(snapshot.activity);
      _acceptCounts(
        snapshot.page.topbarCounts!, snapshot.activity.startedAtMilliseconds,
      );
      _pendingInboxIncrease = (_observedCounts?.notes ?? 0) >
          snapshot.activity.unreadCount;
      return snapshot.activity;
    } catch (_) {
      if (identical(_faNotificationService, svc) && generation == _counterSessionGeneration) {
        _inboxRetryAt = DateTime.now().millisecondsSinceEpoch + _interval.inMilliseconds;
      }
      return null;
    }
  }

  Future<NotesInboxSnapshot?> _loadInbox() async {
    final repository = _notesRepository;
    if (repository == null) {
      return null;
    }
    await _noteTrackingReady;
    final didInitialize = await repository.loadDidFirstRunSkip();
    if (!identical(repository, _notesRepository) || !_isResumed) {
      return null;
    }
    final page = await repository.fetchPage(folder: 'inbox', page: 1);
    if (!identical(repository, _notesRepository) || page.topbarCounts == null) {
      return null;
    }
    final messages = <Message>[...page.messages];
    var fetchedPage2 = false;
    if (!didInitialize || shouldFetchSecondInboxPage(
      page1Messages: page.messages,
      shownNoteIds: await repository.getShownNoteIds(),
      seenNoteIds: await repository.getSeenNoteIds(),
      topbarNotes: page.topbarCounts!.notes,
    )) {
      if (!identical(repository, _notesRepository)) {
        return null;
      }
      messages.addAll(await repository.fetchMessages(folder: 'inbox', page: 2));
      fetchedPage2 = true;
    }
    if (!identical(repository, _notesRepository)) {
      return null;
    }
    final activity = NoteActivitySnapshot(
      messages: List<Message>.unmodifiable(messages.map((message) => Message(
        id: message.id, subject: message.subject, sender: message.sender,
        recipient: message.recipient, date: message.date, link: message.link,
        isUnread: message.isUnread,
      ))),
      startedAtMilliseconds: page.startedAtMilliseconds ??
          DateTime.now().millisecondsSinceEpoch,
      completedAtMilliseconds: fetchedPage2
          ? DateTime.now().millisecondsSinceEpoch
          : page.completedAtMilliseconds,
      unreadCount: page.topbarCounts!.notes,
      fetchedPage2: fetchedPage2,
    );
    if (!didInitialize) {
      await repository.markUnreadMessagesAsShown(messages);
      await repository.markMessagesAsSeen(messages);
      await repository.setFirstRunSkipDone();
    }
    if (!identical(repository, _notesRepository)) {
      return null;
    }
    unawaited(_handleInboxArrivals(repository, messages, didInitialize));
    return NotesInboxSnapshot(page: page, activity: activity);
  }

  Future<void> _handleInboxArrivals(
    NotesRepository repository, List<Message> messages, bool didInitialize,
  ) async {
    try {
      await repository.handleNewUnreadMessages(
        fetchedInbox: messages, previousTopId: null, didFirstRunSkip: didInitialize,
      );
      if (identical(repository, _notesRepository)) {
        await repository.markMessagesAsSeen(messages);
      }
    } catch (_) {}
  }

  Future<void> _runOnce(FaNotificationStatePort svc,
      {required String source}) async {
    if (!identical(_faNotificationService, svc)) {
      return;
    }
    final stopwatch = Stopwatch()..start();
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final generation = _counterSessionGeneration;
    _notificationShownInCurrentRun = false;
    try {
      await _noteTrackingReady;
      if (!identical(_faNotificationService, svc) ||
          generation != _counterSessionGeneration || !_isResumed) {
        return;
      }
      await svc.fetchNotifications();
    } catch (_) {
      if (!identical(_faNotificationService, svc) || generation != _counterSessionGeneration) {
        return;
      }
      _notificationsRetryAt = DateTime.now().millisecondsSinceEpoch +
          _interval.inMilliseconds;
      return;
    }
    if (!identical(_faNotificationService, svc)) {
      return;
    }
    if (generation != _counterSessionGeneration) {
      return;
    }
    if (svc.errorMessage != null || svc.listCounts == null ||
        !svc.hasValidLatestCountsSnapshot) {
      _notificationsRetryAt = DateTime.now().millisecondsSinceEpoch +
          _interval.inMilliseconds;
      await appAnalytics.logNotificationCheckCompleted(
        executionContext: appAnalytics.foregroundContext(source),
        triggerSource: source,
        outcome: NotificationCheckOutcome.failed,
        notificationShown: false,
        durationMilliseconds: stopwatch.elapsedMilliseconds,
      );
      return;
    }
    _notificationsRetryAt = 0;
    _nextNotificationsAt = (svc.listFetchedAtMilliseconds ?? startedAt) +
        _interval.inMilliseconds;
    if (!_acceptCounts(svc.listCounts!, svc.listStartedAtMilliseconds ?? startedAt) &&
        _observedCounts != null) {
      svc.applyTopbarCounts(_observedCounts!);
    }
    final cached = NotesRefreshService().latestInboxSnapshot;
    NoteActivitySnapshot? noteSnapshot = cached?.activity;
    if (cached != null) {
      _rememberInboxCheck(cached.activity);
    }
    if (cached == null || _pendingInboxIncrease ||
        DateTime.now().millisecondsSinceEpoch >= _nextInboxAt) {
      noteSnapshot = await _refreshInbox();
    }
    if (!identical(_faNotificationService, svc) ||
        generation != _counterSessionGeneration) {
      return;
    }
    await _maybeSendActivitiesNotification(
      _observedCounts ?? svc.latestCounts,
      source: source,
      existingNoteActivitySnapshot: noteSnapshot,
    );
    await appAnalytics.logNotificationCheckCompleted(
      executionContext: appAnalytics.foregroundContext(source),
      triggerSource: source,
      outcome: _notificationShownInCurrentRun
          ? NotificationCheckOutcome.contentFound
          : NotificationCheckOutcome.empty,
      notificationShown: _notificationShownInCurrentRun,
      durationMilliseconds: stopwatch.elapsedMilliseconds,
    );
  }

  int get _notificationsDueAt {
    final listTime = _faNotificationService?.listFetchedAtMilliseconds;
    var due = _nextNotificationsAt;
    if (listTime != null) {
      final listDue = listTime + _interval.inMilliseconds;
      if (_notificationsScreenVisible || listDue > due) {
        due = listDue;
      }
    }
    return due > _notificationsRetryAt ? due : _notificationsRetryAt;
  }

  int get _inboxDueAt =>
      _nextInboxAt > _inboxRetryAt ? _nextInboxAt : _inboxRetryAt;

  void _ensureTimer() {
    _scheduleTimer();
  }

  void _resetTimer() {
    _scheduleTimer();
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = null;
    if (_faNotificationService == null || !_isResumed || _inFlight != null) {
      return;
    }
    final due = _notificationsDueAt < _inboxDueAt
        ? _notificationsDueAt : _inboxDueAt;
    final remaining = due - DateTime.now().millisecondsSinceEpoch;
    _timer = Timer(Duration(milliseconds: remaining > 0 ? remaining : 1), () {
      unawaited(_runDueChecks());
    });
  }

  Future<void> _runDueChecks() async {
    final svc = _faNotificationService;
    final generation = _counterSessionGeneration;
    if (svc == null || !_isResumed) {
      return;
    }
    final existing = _inFlight;
    if (existing != null) {
      await existing;
      _scheduleTimer();
      return;
    }
    if (DateTime.now().millisecondsSinceEpoch >= _inboxDueAt) {
      late final Future<void> operation;
      operation = Future<void>.microtask(() async {
        final snapshot = await _refreshInbox();
        if (!identical(_faNotificationService, svc) ||
            generation != _counterSessionGeneration || !_isResumed) {
          return;
        }
        if (snapshot != null && _observedCounts != null) {
          await _maybeSendActivitiesNotification(
            _observedCounts!, source: 'notes_timer',
            existingNoteActivitySnapshot: snapshot,
          );
        }
      }).whenComplete(() {
        if (identical(_inFlight, operation)) {
          _inFlight = null;
        }
      });
      _inFlight = operation;
      await operation;
    }
    if (!identical(_faNotificationService, svc) ||
        generation != _counterSessionGeneration || !_isResumed) {
      return;
    }
    if (DateTime.now().millisecondsSinceEpoch >= _notificationsDueAt) {
      await triggerNow(resetTimer: false, source: 'timer');
    }
    _scheduleTimer();
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
    required String source,
    NoteActivitySnapshot? existingNoteActivitySnapshot,
  }) async {
    final activitiesStateStore = ActivitiesNotificationStateStore();
    final generation = _counterSessionGeneration;
    final service = _faNotificationService;
    final foregroundEntryCheck =
        _foregroundEntryCheckPending || _isForegroundEntrySource(source);
    var deferredForResume = false;
    try {
      final noteActivitySnapshot = existingNoteActivitySnapshot;
      if (noteActivitySnapshot != null) {
        currentCounts = NotificationCounts(
          submissions: currentCounts.submissions,
          watches: currentCounts.watches,
          comments: currentCounts.comments,
          favorites: currentCounts.favorites,
          journals: currentCounts.journals,
          notes: noteActivitySnapshot.startedAtMilliseconds >= _lastCounterStartedAt
              ? noteActivitySnapshot.unreadCount : currentCounts.notes,
        );
        await ManualNoteActivityStore().reconcile(noteActivitySnapshot);
      }
      currentCounts = await activitiesStateStore
          .normalizeUnreadNoteCounts(currentCounts);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      if (generation != _counterSessionGeneration ||
          !identical(service, _faNotificationService) || service == null) {
        return;
      }

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

      if (_pendingNotesEntryAcknowledgement &&
          _notesScreenVisible &&
          _isResumed) {
        await activitiesStateStore.acknowledgeVisibleCounts(
          currentCounts: currentCounts,
          acknowledgeNotes: true,
        );
        _pendingNotesEntryAcknowledgement = false;
      }

      final acknowledgeVisible = !foregroundEntryCheck && _isResumed;
      if (acknowledgeVisible) {
        await _acknowledgeVisibleCounts(
          activitiesStateStore,
          currentCounts,
        );
      }
      final RecordedActivitiesDiff recordedDiff =
          await activitiesStateStore.recordAndDiffCurrentCounts(
        currentCounts: currentCounts,
        noteActivitySnapshot: noteActivitySnapshot,
      );
      final ActivitiesDiff unacknowledgedDiff =
          recordedDiff.unacknowledged;
      await activitiesStateStore.synchronizeDisabledCounts(
        currentCounts: currentCounts,
        submissionsEnabled: submissionsEnabled,
        watchesEnabled: watchesEnabled,
        commentsEnabled: commentsEnabled,
        favoritesEnabled: favoritesEnabled,
        journalsEnabled: journalsEnabled,
        notesEnabled: notesEnabled,
      );

      final bool acknowledgeRequested =
          await activitiesStateStore.consumeAcknowledgeOnNextForegroundFetch();
      if (acknowledgeRequested) {
        await activitiesStateStore.acknowledgeCurrentCounts(
          currentCounts: currentCounts,
        );
        await NotificationService().cancelActivityNotification(
          source: 'foregroundAcknowledge',
        );
        return;
      }

      final bool submissionsNotificationEnabled = submissionsEnabled &&
          (!acknowledgeVisible || !_submissionsScreenVisible);
      final bool watchesNotificationEnabled = watchesEnabled &&
          (!acknowledgeVisible || !_acknowledgeWatchesVisible);
      final bool commentsNotificationEnabled = commentsEnabled &&
          (!acknowledgeVisible || !_acknowledgeCommentsVisible);
      final bool favoritesNotificationEnabled = favoritesEnabled &&
          (!acknowledgeVisible || !_acknowledgeFavoritesVisible);
      final bool journalsNotificationEnabled = journalsEnabled &&
          (!acknowledgeVisible || !_acknowledgeJournalsVisible);
      final bool notesNotificationEnabled = notesEnabled;
      final displayDecision = _countChangePolicy.notificationDecision(
        diff: unacknowledgedDiff,
        submissionsEnabled: submissionsNotificationEnabled,
        watchesEnabled: watchesNotificationEnabled,
        commentsEnabled: commentsNotificationEnabled,
        favoritesEnabled: favoritesNotificationEnabled,
        journalsEnabled: journalsNotificationEnabled,
        notesEnabled: notesNotificationEnabled,
      );
      final enabledIncreases = displayDecision.increasedBy;
      if (!displayDecision.shouldNotify) {
        return;
      }

      final alreadyShown =
          await activitiesStateStore.areCurrentCountsLastShown(
        currentCounts: currentCounts,
        submissionsEnabled: submissionsNotificationEnabled,
        watchesEnabled: watchesNotificationEnabled,
        commentsEnabled: commentsNotificationEnabled,
        favoritesEnabled: favoritesNotificationEnabled,
        journalsEnabled: journalsNotificationEnabled,
        notesEnabled: notesNotificationEnabled &&
            recordedDiff.noteActivityIds == null,
      );
      if (alreadyShown &&
          (!notesNotificationEnabled ||
              (recordedDiff.noteActivityIds?.isEmpty ?? true))) {
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

      if (Platform.isIOS &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await activitiesStateStore.deferActivityNotification(
          currentCounts: currentCounts,
          previousObservedCounts: recordedDiff.observed.previous,
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
      if (generation != _counterSessionGeneration ||
          !identical(service, _faNotificationService)) {
        return;
      }
      await notificationService.showNotification(
        NotificationService.activityNotificationId,
        'New FA Activity',
        messageBody,
        Platform.isIOS
            ? activityPayloadWithCounts('activity_fa_activity', currentCounts)
            : 'activity_fa_activity',
        'activities',
        validateNoteActivity: enabledIncreases.notes > 0,
        activityNoteIds: recordedDiff.noteActivityIds,
        isCancelled: () => generation != _counterSessionGeneration ||
            !identical(service, _faNotificationService) ||
            (Platform.isIOS &&
                WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed),
      );
      if (generation != _counterSessionGeneration || !identical(service, _faNotificationService)) {
        return;
      }
      _notificationShownInCurrentRun = true;
      if (!Platform.isIOS) {
        await appAnalytics.logNotificationDisplayed(
          executionContext: appAnalytics.foregroundContext(source),
          notificationType: 'activity',
        );
      }
      await activitiesStateStore.markActivityNotificationShown(
        currentCounts: currentCounts,
        body: messageBody,
        noteActivityIds: notesEnabled ? recordedDiff.noteActivityIds : null,
      );
      await notification_badge.rememberActivityNotification(
        NotificationService.activityNotificationId,
      );
      if (Platform.isIOS) {
        unawaited(appAnalytics.logNotificationDisplayed(
          executionContext: appAnalytics.foregroundContext(source),
          notificationType: 'activity',
        ));
      }
      _pendingResumeActivityNotification = false;
      debugPrint(
        '[ACTIVITY_NOTIF] producer=foreground_polling shown body=$messageBody',
      );
    } catch (_) {
    } finally {
      if (foregroundEntryCheck && !deferredForResume &&
          generation == _counterSessionGeneration && identical(service, _faNotificationService)) {
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
        if (realResume && _notesScreenVisible) {
          _beginNotesEntryAcknowledgement();
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now >= _notificationsDueAt ||
            (_notificationsScreenVisible && _notificationsNeedRefresh) ||
            _observedCounts == null) {
          unawaited(triggerNow(resetTimer: false, source: 'lifecycle_resumed'));
        } else if (now >= _inboxDueAt) {
          unawaited(_runDueChecks());
        } else {
          unawaited(handleExternalCounts(
            currentCounts: _observedCounts!, resetTimer: false,
            source: 'lifecycle_resumed', startedAtMilliseconds: _lastCounterStartedAt,
          ));
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
