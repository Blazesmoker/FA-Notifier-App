import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/features/notifications/domain/notification_counts.dart';

/// Single source of truth for "New FA Activity" de-duping.
///
/// Persisted (SharedPreferences) so it works across:
/// - background isolate (Workmanager)
/// - foreground UI refresh (HomeDrawer)
/// - app restarts / cold starts
///
/// Semantics are **last-seen snapshot** (not max-ever):
/// - After each fetch we always store the current per-category counts.
/// - "Should notify" is decided by comparing current vs previous snapshot,
///   category-by-category (no fragile sum logic).
class ActivitiesNotificationStateStore {
  static final ActivitiesNotificationStateStore _i =
      ActivitiesNotificationStateStore._internal();
  factory ActivitiesNotificationStateStore() => _i;
  ActivitiesNotificationStateStore._internal();

  // Per-category persisted baselines.
  static const String _kSubmissions = 'last_seen_activities_submissions';
  static const String _kWatches = 'last_seen_activities_watches';
  static const String _kComments = 'last_seen_activities_comments';
  static const String _kFavorites = 'last_seen_activities_favorites';
  static const String _kJournals = 'last_seen_activities_journals';
  static const String _kNotes = 'last_seen_activities_notes';

  static const String _kLastShownSubmissions =
      'last_shown_activities_submissions';
  static const String _kLastShownWatches = 'last_shown_activities_watches';
  static const String _kLastShownComments = 'last_shown_activities_comments';
  static const String _kLastShownFavorites = 'last_shown_activities_favorites';
  static const String _kLastShownJournals = 'last_shown_activities_journals';
  static const String _kLastShownNotes = 'last_shown_activities_notes';
  static const String _kLastShownBody = 'last_shown_activities_body';

  static const String kLastSeenUpdatedAtMsKey = 'last_seen_activities_at_ms';
  static const String kLastShownUpdatedAtMsKey = 'last_shown_activities_at_ms';

  // In-isolate mutex to avoid duplicate notifications caused by overlapping
  // refresh triggers (timer + lifecycle + notification tap refresh).
  static Future<void> _mutex = Future<void>.value();

  static Future<T> _withMutex<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _mutex = _mutex.then((_) async {
      try {
        completer.complete(await fn());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Loads the last-seen per-category counts.
  Future<NotificationCounts> loadLastSeenCounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return NotificationCounts(
      submissions: prefs.getInt(_kSubmissions) ?? 0,
      watches: prefs.getInt(_kWatches) ?? 0,
      comments: prefs.getInt(_kComments) ?? 0,
      favorites: prefs.getInt(_kFavorites) ?? 0,
      journals: prefs.getInt(_kJournals) ?? 0,
      notes: prefs.getInt(_kNotes) ?? 0,
    );
  }

  /// Computes per-category increases from the stored last-seen snapshot and
  /// then stores [currentCounts] as the new last-seen snapshot.
  ///
  /// Migration behavior:
  /// - If a key is missing (null), we treat its previous value as the current
  ///   value, so the first run after an update does **not** spam notifications.
  Future<ActivitiesDiff> diffAndUpdateLastSeen({
    required NotificationCounts currentCounts,
  }) async {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      int prevSubmissions = prefs.getInt(_kSubmissions) ?? currentCounts.submissions;
      int prevWatches = prefs.getInt(_kWatches) ?? currentCounts.watches;
      int prevComments = prefs.getInt(_kComments) ?? currentCounts.comments;
      int prevFavorites = prefs.getInt(_kFavorites) ?? currentCounts.favorites;
      int prevJournals = prefs.getInt(_kJournals) ?? currentCounts.journals;
      int prevNotes = prefs.getInt(_kNotes) ?? currentCounts.notes;

      final previousCounts = NotificationCounts(
        submissions: prevSubmissions,
        watches: prevWatches,
        comments: prevComments,
        favorites: prevFavorites,
        journals: prevJournals,
        notes: prevNotes,
      );

      final increasedBy = NotificationCounts(
        submissions: currentCounts.submissions > prevSubmissions
            ? currentCounts.submissions - prevSubmissions
            : 0,
        watches: currentCounts.watches > prevWatches
            ? currentCounts.watches - prevWatches
            : 0,
        comments: currentCounts.comments > prevComments
            ? currentCounts.comments - prevComments
            : 0,
        favorites: currentCounts.favorites > prevFavorites
            ? currentCounts.favorites - prevFavorites
            : 0,
        journals: currentCounts.journals > prevJournals
            ? currentCounts.journals - prevJournals
            : 0,
        notes: currentCounts.notes > prevNotes ? currentCounts.notes - prevNotes : 0,
      );

      // Always store the current snapshot (last-seen semantics), even if it decreased.
      await prefs.setInt(_kSubmissions, currentCounts.submissions);
      await prefs.setInt(_kWatches, currentCounts.watches);
      await prefs.setInt(_kComments, currentCounts.comments);
      await prefs.setInt(_kFavorites, currentCounts.favorites);
      await prefs.setInt(_kJournals, currentCounts.journals);
      await prefs.setInt(_kNotes, currentCounts.notes);
      await prefs.setInt(
        kLastSeenUpdatedAtMsKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      return ActivitiesDiff(
        previous: previousCounts,
        current: currentCounts,
        increasedBy: increasedBy,
      );
    });
  }

  Future<bool> isDuplicateShownNotification({
    required NotificationCounts currentCounts,
    required String body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final String? lastBody = prefs.getString(_kLastShownBody);
    if (lastBody == null || lastBody != body) return false;

    return prefs.getInt(_kLastShownSubmissions) == currentCounts.submissions &&
        prefs.getInt(_kLastShownWatches) == currentCounts.watches &&
        prefs.getInt(_kLastShownComments) == currentCounts.comments &&
        prefs.getInt(_kLastShownFavorites) == currentCounts.favorites &&
        prefs.getInt(_kLastShownJournals) == currentCounts.journals &&
        prefs.getInt(_kLastShownNotes) == currentCounts.notes;
  }

  Future<void> markActivityNotificationShown({
    required NotificationCounts currentCounts,
    required String body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastShownSubmissions, currentCounts.submissions);
    await prefs.setInt(_kLastShownWatches, currentCounts.watches);
    await prefs.setInt(_kLastShownComments, currentCounts.comments);
    await prefs.setInt(_kLastShownFavorites, currentCounts.favorites);
    await prefs.setInt(_kLastShownJournals, currentCounts.journals);
    await prefs.setInt(_kLastShownNotes, currentCounts.notes);
    await prefs.setString(_kLastShownBody, body);
    await prefs.setInt(
      kLastShownUpdatedAtMsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class ActivitiesDiff {
  final NotificationCounts previous;
  final NotificationCounts current;
  final NotificationCounts increasedBy;

  const ActivitiesDiff({
    required this.previous,
    required this.current,
    required this.increasedBy,
  });

  bool get hasAnyIncrease =>
      increasedBy.submissions > 0 ||
      increasedBy.watches > 0 ||
      increasedBy.comments > 0 ||
      increasedBy.favorites > 0 ||
      increasedBy.journals > 0 ||
      increasedBy.notes > 0;

  bool hasNonZeroPreviousIncrease(NotificationCounts enabledIncreases) {
    return (enabledIncreases.submissions > 0 && previous.submissions > 0) ||
        (enabledIncreases.watches > 0 && previous.watches > 0) ||
        (enabledIncreases.comments > 0 && previous.comments > 0) ||
        (enabledIncreases.favorites > 0 && previous.favorites > 0) ||
        (enabledIncreases.journals > 0 && previous.journals > 0) ||
        (enabledIncreases.notes > 0 && previous.notes > 0);
  }
}


