// lib/utils/notification_counts.dart

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
