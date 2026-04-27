import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/features/notifications/domain/notification_counts.dart';
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
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _inFlight = null;
    _refreshSub?.cancel();
    _refreshSub = null;
    _faNotificationService = null;
    if (_observerAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
  }

  void resetSchedule() {
    if (_faNotificationService == null) return;
    _resetTimer();
  }

  Future<void> triggerNow({required bool resetTimer, required String source}) {
    if (resetTimer) {
      _resetTimer();
    }
    final existing = _inFlight;
    if (existing != null) return existing;

    final svc = _faNotificationService;
    if (svc == null) return Future.value();

    final future = _runOnce(svc, source: source).whenComplete(() {
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
    await _maybeSendActivitiesNotification(svc.latestCounts);
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
    final int previous = current - increasedBy;
    if (increasedBy > 0 && previous > 0) {
      return '$current$suffix(+${increasedBy})';
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
      NotificationCounts currentCounts) async {
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

      final ActivitiesDiff diff = await ActivitiesNotificationStateStore()
          .diffAndUpdateLastSeen(currentCounts: currentCounts);

      final NotificationCounts enabledIncreases = NotificationCounts(
        submissions: submissionsEnabled ? diff.increasedBy.submissions : 0,
        watches: watchesEnabled ? diff.increasedBy.watches : 0,
        comments: commentsEnabled ? diff.increasedBy.comments : 0,
        favorites: favoritesEnabled ? diff.increasedBy.favorites : 0,
        journals: journalsEnabled ? diff.increasedBy.journals : 0,
        notes: notesEnabled ? diff.increasedBy.notes : 0,
      );

      final bool shouldNotify = enabledIncreases.submissions > 0 ||
          enabledIncreases.watches > 0 ||
          enabledIncreases.comments > 0 ||
          enabledIncreases.favorites > 0 ||
          enabledIncreases.journals > 0 ||
          enabledIncreases.notes > 0;

      if (!shouldNotify) return;

      final bool soundActivitiesEnabled =
          prefs.getBool('sound_new_activities_enabled') ?? true;
      final bool vibrationActivitiesEnabled =
          prefs.getBool('vibration_new_activities_enabled') ?? true;
      if (!soundActivitiesEnabled && !vibrationActivitiesEnabled) return;

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

      final notificationService = NotificationService();
      final int activityNotificationId =
          await notificationService.allocateActivityNotificationId();

      await notificationService.showNotification(
        activityNotificationId,
        'New FA Activity',
        messageBody,
        'activity_fa_activity',
        'activities',
      );
    } catch (_) {}
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
      if (realResume) {
        triggerNow(resetTimer: true, source: 'lifecycle_resumed');
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
