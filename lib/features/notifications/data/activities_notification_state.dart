import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/features/notifications/domain/notification_counts.dart';

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

  static const String _kLastShownSubmissions =
      'last_shown_activities_submissions';
  static const String _kLastShownWatches = 'last_shown_activities_watches';
  static const String _kLastShownComments = 'last_shown_activities_comments';
  static const String _kLastShownFavorites = 'last_shown_activities_favorites';
  static const String _kLastShownJournals = 'last_shown_activities_journals';
  static const String _kLastShownNotes = 'last_shown_activities_notes';
  static const String _kLastShownBody = 'last_shown_activities_body';
  static const String _kAcknowledgeOnNextForegroundFetch =
      'acknowledge_activities_on_next_foreground_fetch';
  static const String _kBaselineSchemaVersion =
      'activities_baseline_schema_version';
  static const int _baselineSchemaVersion = 1;

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

  Future<ActivitiesDiff> diffFromAcknowledged({
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
        return ActivitiesDiff(
          previous: currentCounts,
          current: currentCounts,
          increasedBy: NotificationCounts(
            submissions: 0,
            watches: 0,
            comments: 0,
            favorites: 0,
            journals: 0,
            notes: 0,
          ),
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

      await _lowerBaselineForDecreases(
        prefs,
        previousCounts: previousCounts,
        currentCounts: currentCounts,
      );

      return ActivitiesDiff(
        previous: previousCounts,
        current: currentCounts,
        increasedBy: increasedBy,
      );
    });
  }

  Future<void> acknowledgeCurrentCounts({
    required NotificationCounts currentCounts,
  }) async {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      await _saveLastSeenCounts(prefs, currentCounts);
      await _clearLastShownNotification(prefs);
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

  Future<bool> areCurrentCountsLastShown({
    required NotificationCounts currentCounts,
  }) {
    return _withMutex(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      if (prefs.getString(_kLastShownBody) == null) return false;

      return prefs.getInt(_kLastShownSubmissions) ==
              currentCounts.submissions &&
          prefs.getInt(_kLastShownWatches) == currentCounts.watches &&
          prefs.getInt(_kLastShownComments) == currentCounts.comments &&
          prefs.getInt(_kLastShownFavorites) == currentCounts.favorites &&
          prefs.getInt(_kLastShownJournals) == currentCounts.journals &&
          prefs.getInt(_kLastShownNotes) == currentCounts.notes;
    });
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
      if (acknowledgeSubmissions) {
        await prefs.setInt(_kSubmissions, currentCounts.submissions);
      }
      if (acknowledgeWatches) {
        await prefs.setInt(_kWatches, currentCounts.watches);
      }
      if (acknowledgeComments) {
        await prefs.setInt(_kComments, currentCounts.comments);
      }
      if (acknowledgeFavorites) {
        await prefs.setInt(_kFavorites, currentCounts.favorites);
      }
      if (acknowledgeJournals) {
        await prefs.setInt(_kJournals, currentCounts.journals);
      }
      if (acknowledgeNotes) {
        await prefs.setInt(_kNotes, currentCounts.notes);
      }
      if (acknowledgeSubmissions ||
          acknowledgeWatches ||
          acknowledgeComments ||
          acknowledgeFavorites ||
          acknowledgeJournals ||
          acknowledgeNotes) {
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
    });
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


