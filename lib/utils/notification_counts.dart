// lib/utils/notification_counts.dart

import 'package:shared_preferences/shared_preferences.dart';

/// Holds counts for each notification category.
class NotificationCounts {
  final int submissions;
  final int watches;
  final int comments;
  final int favorites;
  final int journals;
  final int notes;

  NotificationCounts({
    required this.submissions,
    required this.watches,
    required this.comments,
    required this.favorites,
    required this.journals,
    required this.notes,
  });


  bool isDifferentFrom(NotificationCounts other) {
    return submissions != other.submissions ||
        watches != other.watches ||
        comments != other.comments ||
        favorites != other.favorites ||
        journals != other.journals ||
        notes != other.notes;
  }

  @override
  String toString() {
    return 'S:$submissions, W:$watches, C:$comments, F:$favorites, J:$journals, N:$notes';
  }
}


class NotificationCountsStorage {
  static const _keySubmissions = 'notif_submissions';
  static const _keyWatches = 'notif_watches';
  static const _keyComments = 'notif_comments';
  static const _keyFavorites = 'notif_favorites';
  static const _keyJournals = 'notif_journals';
  static const _keyNotes = 'notif_notes';


  static Future<void> saveCounts(NotificationCounts counts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySubmissions, counts.submissions);
    await prefs.setInt(_keyWatches, counts.watches);
    await prefs.setInt(_keyComments, counts.comments);
    await prefs.setInt(_keyFavorites, counts.favorites);
    await prefs.setInt(_keyJournals, counts.journals);
    await prefs.setInt(_keyNotes, counts.notes);
  }


  static Future<NotificationCounts> loadCounts() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationCounts(
      submissions: prefs.getInt(_keySubmissions) ?? 0,
      watches: prefs.getInt(_keyWatches) ?? 0,
      comments: prefs.getInt(_keyComments) ?? 0,
      favorites: prefs.getInt(_keyFavorites) ?? 0,
      journals: prefs.getInt(_keyJournals) ?? 0,
      notes: prefs.getInt(_keyNotes) ?? 0,
    );
  }
}
