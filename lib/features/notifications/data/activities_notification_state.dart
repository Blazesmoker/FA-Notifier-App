import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/notifications/domain/activity_count_change_policy.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

class ActivitiesNotificationStateStore {
  static final ActivitiesNotificationStateStore _i =
      ActivitiesNotificationStateStore._internal();
  factory ActivitiesNotificationStateStore() => _i;
  ActivitiesNotificationStateStore._internal();

  static const String _kSubmissions = 'last_seen_activities_submissions';
  static const String _kWatches = 'last_seen_activities_watches';
  static const String _kComments = 'last_seen_activities_comments';
  static const String _kFavorites = 'last_seen_activities_favorites';
  static const String _kJournals = 'last_seen_activities_journals';
  static const String _kNotes = 'last_seen_activities_notes';

  static const String _kObservedSubmissions =
      'last_observed_activities_submissions';
  static const String _kObservedWatches = 'last_observed_activities_watches';
  static const String _kObservedComments = 'last_observed_activities_comments';
  static const String _kObservedFavorites =
      'last_observed_activities_favorites';
  static const String _kObservedJournals = 'last_observed_activities_journals';
  static const String _kObservedNotes = 'last_observed_activities_notes';
  static const String _kObservedSchemaVersion =
      'activities_observed_schema_version';
  static const int _observedSchemaVersion = 1;

  static const String _kLastShownSubmissions =
      'last_shown_activities_submissions';
  static const String _kLastShownWatches = 'last_shown_activities_watches';
  static const String _kLastShownComments = 'last_shown_activities_comments';
  static const String _kLastShownFavorites = 'last_shown_activities_favorites';
  static const String _kLastShownJournals = 'last_shown_activities_journals';
  static const String _kLastShownNotes = 'last_shown_activities_notes';
  static const String _kLastShownBody = 'last_shown_activities_body';
  static const String _kDeferredSubmissions =
      'deferred_activities_submissions';
  static const String _kDeferredWatches = 'deferred_activities_watches';
  static const String _kDeferredComments = 'deferred_activities_comments';
  static const String _kDeferredFavorites = 'deferred_activities_favorites';
  static const String _kDeferredJournals = 'deferred_activities_journals';
  static const String _kDeferredNotes = 'deferred_activities_notes';
  static const String _kDeferredBody = 'deferred_activities_body';
  static const String _kDeferredUpdatedAtMs = 'deferred_activities_at_ms';
  static const String _kAcknowledgeOnNextForegroundFetch =
      'acknowledge_activities_on_next_foreground_fetch_v2';
  static const String _kBaselineSchemaVersion =
      'activities_baseline_schema_version';
  static const int _baselineSchemaVersion = 1;

  static const ActivityCountChangePolicy _countChangePolicy =
      ActivityCountChangePolicy();

  static const String kLastSeenUpdatedAtMsKey = 'last_seen_activities_at_ms';
  static const String kLastShownUpdatedAtMsKey = 'last_shown_activities_at_ms';

  static Future<void> _mutex = Future<void>.value();

  static Future<T> _withMutex<T>(Future<T> Function() fn) {
    final operation = _mutex.catchError((_) {}).then((_) => fn());
    _mutex = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

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

  Future<ActivitiesDiff> recordAndDiffCurrentCounts({
    required NotificationCounts currentCounts,
  }) async {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final hasBaseline =
          prefs.getInt(_kBaselineSchemaVersion) == _baselineSchemaVersion &&
          prefs.containsKey(_kSubmissions) &&
          prefs.containsKey(_kWatches) &&
          prefs.containsKey(_kComments) &&
          prefs.containsKey(_kFavorites) &&
          prefs.containsKey(_kJournals) &&
          prefs.containsKey(_kNotes);
      if (!hasBaseline) {
        await _saveLastSeenCounts(prefs, currentCounts);
        await _saveLastObservedCounts(prefs, currentCounts);
        return _countChangePolicy.diff(
          previous: currentCounts,
          current: currentCounts,
        );
      }

      final prevSubmissions = prefs.getInt(_kSubmissions) ?? 0;
      final prevWatches = prefs.getInt(_kWatches) ?? 0;
      final prevComments = prefs.getInt(_kComments) ?? 0;
      final prevFavorites = prefs.getInt(_kFavorites) ?? 0;
      final prevJournals = prefs.getInt(_kJournals) ?? 0;
      final prevNotes = prefs.getInt(_kNotes) ?? 0;

      final previousCounts = NotificationCounts(
        submissions: prevSubmissions,
        watches: prevWatches,
        comments: prevComments,
        favorites: prevFavorites,
        journals: prevJournals,
        notes: prevNotes,
      );

      final previousObservedCounts = _loadPreviousObservedCounts(
        prefs,
        fallback: previousCounts,
      );
      final diff = _countChangePolicy.diff(
        previous: previousObservedCounts,
        current: currentCounts,
      );

      await _lowerBaselineForDecreases(
        prefs,
        previousCounts: previousCounts,
        currentCounts: currentCounts,
      );
      await _saveLastObservedCounts(prefs, currentCounts);

      return diff;
    });
  }

  Future<void> acknowledgeCurrentCounts({
    required NotificationCounts currentCounts,
  }) async {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      await _saveLastSeenCounts(prefs, currentCounts);
      await _saveLastObservedCounts(prefs, currentCounts);
      await _clearLastShownNotification(prefs);
      await _clearDeferredActivityNotification(prefs);
    });
  }

  Future<void> deferActivityNotification({
    required NotificationCounts currentCounts,
    required NotificationCounts previousObservedCounts,
    required String body,
  }) {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kDeferredSubmissions, currentCounts.submissions);
      await prefs.setInt(_kDeferredWatches, currentCounts.watches);
      await prefs.setInt(_kDeferredComments, currentCounts.comments);
      await prefs.setInt(_kDeferredFavorites, currentCounts.favorites);
      await prefs.setInt(_kDeferredJournals, currentCounts.journals);
      await prefs.setInt(_kDeferredNotes, currentCounts.notes);
      await prefs.setString(_kDeferredBody, body);
      await prefs.setInt(
        _kDeferredUpdatedAtMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      await _saveLastObservedCounts(prefs, previousObservedCounts);
    });
  }

  Future<void> acknowledgeVisibleCounts({
    required NotificationCounts currentCounts,
    bool acknowledgeSubmissions = false,
    bool acknowledgeWatches = false,
    bool acknowledgeComments = false,
    bool acknowledgeFavorites = false,
    bool acknowledgeJournals = false,
    bool acknowledgeNotes = false,
  }) async {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      final changed = await _saveSelectedLastSeenCounts(
        prefs,
        currentCounts,
        acknowledgeSubmissions: acknowledgeSubmissions,
        acknowledgeWatches: acknowledgeWatches,
        acknowledgeComments: acknowledgeComments,
        acknowledgeFavorites: acknowledgeFavorites,
        acknowledgeJournals: acknowledgeJournals,
        acknowledgeNotes: acknowledgeNotes,
      );
      if (changed) {
        await prefs.setInt(
          kLastSeenUpdatedAtMsKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    });
  }

  Future<void> synchronizeDisabledCounts({
    required NotificationCounts currentCounts,
    required bool submissionsEnabled,
    required bool watchesEnabled,
    required bool commentsEnabled,
    required bool favoritesEnabled,
    required bool journalsEnabled,
    required bool notesEnabled,
  }) async {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final changed = await _saveSelectedLastSeenCounts(
        prefs,
        currentCounts,
        acknowledgeSubmissions: !submissionsEnabled,
        acknowledgeWatches: !watchesEnabled,
        acknowledgeComments: !commentsEnabled,
        acknowledgeFavorites: !favoritesEnabled,
        acknowledgeJournals: !journalsEnabled,
        acknowledgeNotes: !notesEnabled,
      );
      if (changed) {
        await prefs.setInt(
          kLastSeenUpdatedAtMsKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      if (prefs.getString(_kLastShownBody) == null) return;
      if (!submissionsEnabled) {
        await prefs.setInt(_kLastShownSubmissions, currentCounts.submissions);
      }
      if (!watchesEnabled) {
        await prefs.setInt(_kLastShownWatches, currentCounts.watches);
      }
      if (!commentsEnabled) {
        await prefs.setInt(_kLastShownComments, currentCounts.comments);
      }
      if (!favoritesEnabled) {
        await prefs.setInt(_kLastShownFavorites, currentCounts.favorites);
      }
      if (!journalsEnabled) {
        await prefs.setInt(_kLastShownJournals, currentCounts.journals);
      }
      if (!notesEnabled) {
        await prefs.setInt(_kLastShownNotes, currentCounts.notes);
      }
    });
  }

  Future<void> requestAcknowledgeOnNextForegroundFetch() {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAcknowledgeOnNextForegroundFetch, true);
    });
  }

  Future<bool> consumeAcknowledgeOnNextForegroundFetch() async {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final requested =
          prefs.getBool(_kAcknowledgeOnNextForegroundFetch) ?? false;
      if (requested) {
        await prefs.remove(_kAcknowledgeOnNextForegroundFetch);
      }
      return requested;
    });
  }

  Future<void> _saveLastSeenCounts(
    SharedPreferences prefs,
    NotificationCounts counts,
  ) async {
    await prefs.setInt(_kSubmissions, counts.submissions);
    await prefs.setInt(_kWatches, counts.watches);
    await prefs.setInt(_kComments, counts.comments);
    await prefs.setInt(_kFavorites, counts.favorites);
    await prefs.setInt(_kJournals, counts.journals);
    await prefs.setInt(_kNotes, counts.notes);
    await prefs.setInt(_kBaselineSchemaVersion, _baselineSchemaVersion);
    await prefs.setInt(
      kLastSeenUpdatedAtMsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<bool> _saveSelectedLastSeenCounts(
    SharedPreferences prefs,
    NotificationCounts counts, {
    required bool acknowledgeSubmissions,
    required bool acknowledgeWatches,
    required bool acknowledgeComments,
    required bool acknowledgeFavorites,
    required bool acknowledgeJournals,
    required bool acknowledgeNotes,
  }) async {
    var changed = false;
    if (acknowledgeSubmissions) {
      await prefs.setInt(_kSubmissions, counts.submissions);
      changed = true;
    }
    if (acknowledgeWatches) {
      await prefs.setInt(_kWatches, counts.watches);
      changed = true;
    }
    if (acknowledgeComments) {
      await prefs.setInt(_kComments, counts.comments);
      changed = true;
    }
    if (acknowledgeFavorites) {
      await prefs.setInt(_kFavorites, counts.favorites);
      changed = true;
    }
    if (acknowledgeJournals) {
      await prefs.setInt(_kJournals, counts.journals);
      changed = true;
    }
    if (acknowledgeNotes) {
      await prefs.setInt(_kNotes, counts.notes);
      changed = true;
    }
    if (changed) {
      await prefs.setInt(_kBaselineSchemaVersion, _baselineSchemaVersion);
    }
    return changed;
  }

  Future<void> _lowerBaselineForDecreases(
    SharedPreferences prefs, {
    required NotificationCounts previousCounts,
    required NotificationCounts currentCounts,
  }) async {
    bool changed = false;
    if (currentCounts.submissions < previousCounts.submissions) {
      await prefs.setInt(_kSubmissions, currentCounts.submissions);
      changed = true;
    }
    if (currentCounts.watches < previousCounts.watches) {
      await prefs.setInt(_kWatches, currentCounts.watches);
      changed = true;
    }
    if (currentCounts.comments < previousCounts.comments) {
      await prefs.setInt(_kComments, currentCounts.comments);
      changed = true;
    }
    if (currentCounts.favorites < previousCounts.favorites) {
      await prefs.setInt(_kFavorites, currentCounts.favorites);
      changed = true;
    }
    if (currentCounts.journals < previousCounts.journals) {
      await prefs.setInt(_kJournals, currentCounts.journals);
      changed = true;
    }
    if (currentCounts.notes < previousCounts.notes) {
      await prefs.setInt(_kNotes, currentCounts.notes);
      changed = true;
    }
    if (changed) {
      await prefs.setInt(
        kLastSeenUpdatedAtMsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  Future<void> _clearLastShownNotification(SharedPreferences prefs) async {
    await prefs.remove(_kLastShownSubmissions);
    await prefs.remove(_kLastShownWatches);
    await prefs.remove(_kLastShownComments);
    await prefs.remove(_kLastShownFavorites);
    await prefs.remove(_kLastShownJournals);
    await prefs.remove(_kLastShownNotes);
    await prefs.remove(_kLastShownBody);
    await prefs.remove(kLastShownUpdatedAtMsKey);
  }

  Future<void> _clearDeferredActivityNotification(
    SharedPreferences prefs,
  ) async {
    await prefs.remove(_kDeferredSubmissions);
    await prefs.remove(_kDeferredWatches);
    await prefs.remove(_kDeferredComments);
    await prefs.remove(_kDeferredFavorites);
    await prefs.remove(_kDeferredJournals);
    await prefs.remove(_kDeferredNotes);
    await prefs.remove(_kDeferredBody);
    await prefs.remove(_kDeferredUpdatedAtMs);
  }

  NotificationCounts _loadPreviousObservedCounts(
    SharedPreferences prefs, {
    required NotificationCounts fallback,
  }) {
    final hasObservedCounts =
        prefs.getInt(_kObservedSchemaVersion) == _observedSchemaVersion &&
            prefs.containsKey(_kObservedSubmissions) &&
            prefs.containsKey(_kObservedWatches) &&
            prefs.containsKey(_kObservedComments) &&
            prefs.containsKey(_kObservedFavorites) &&
            prefs.containsKey(_kObservedJournals) &&
            prefs.containsKey(_kObservedNotes);
    if (hasObservedCounts) {
      return NotificationCounts(
        submissions: prefs.getInt(_kObservedSubmissions)!,
        watches: prefs.getInt(_kObservedWatches)!,
        comments: prefs.getInt(_kObservedComments)!,
        favorites: prefs.getInt(_kObservedFavorites)!,
        journals: prefs.getInt(_kObservedJournals)!,
        notes: prefs.getInt(_kObservedNotes)!,
      );
    }

    final hasLastShownCounts = prefs.getString(_kLastShownBody) != null &&
        prefs.containsKey(_kLastShownSubmissions) &&
        prefs.containsKey(_kLastShownWatches) &&
        prefs.containsKey(_kLastShownComments) &&
        prefs.containsKey(_kLastShownFavorites) &&
        prefs.containsKey(_kLastShownJournals) &&
        prefs.containsKey(_kLastShownNotes);
    if (hasLastShownCounts) {
      return NotificationCounts(
        submissions: prefs.getInt(_kLastShownSubmissions)!,
        watches: prefs.getInt(_kLastShownWatches)!,
        comments: prefs.getInt(_kLastShownComments)!,
        favorites: prefs.getInt(_kLastShownFavorites)!,
        journals: prefs.getInt(_kLastShownJournals)!,
        notes: prefs.getInt(_kLastShownNotes)!,
      );
    }

    return fallback;
  }

  Future<void> _saveLastObservedCounts(
    SharedPreferences prefs,
    NotificationCounts counts,
  ) async {
    await prefs.setInt(_kObservedSubmissions, counts.submissions);
    await prefs.setInt(_kObservedWatches, counts.watches);
    await prefs.setInt(_kObservedComments, counts.comments);
    await prefs.setInt(_kObservedFavorites, counts.favorites);
    await prefs.setInt(_kObservedJournals, counts.journals);
    await prefs.setInt(_kObservedNotes, counts.notes);
    await prefs.setInt(_kObservedSchemaVersion, _observedSchemaVersion);
  }

  Future<void> markActivityNotificationShown({
    required NotificationCounts currentCounts,
    required String body,
    bool acknowledgeSubmissions = false,
    bool acknowledgeWatches = false,
    bool acknowledgeComments = false,
    bool acknowledgeFavorites = false,
    bool acknowledgeJournals = false,
    bool acknowledgeNotes = false,
  }) {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      final changed = await _saveSelectedLastSeenCounts(
        prefs,
        currentCounts,
        acknowledgeSubmissions: acknowledgeSubmissions,
        acknowledgeWatches: acknowledgeWatches,
        acknowledgeComments: acknowledgeComments,
        acknowledgeFavorites: acknowledgeFavorites,
        acknowledgeJournals: acknowledgeJournals,
        acknowledgeNotes: acknowledgeNotes,
      );
      if (changed) {
        await prefs.setInt(
          kLastSeenUpdatedAtMsKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
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
      await _clearDeferredActivityNotification(prefs);
    });
  }
}
