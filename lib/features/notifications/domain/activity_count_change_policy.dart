import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

class ActivityCountChangePolicy {
  const ActivityCountChangePolicy();

  ActivitiesDiff diff({
    required NotificationCounts previous,
    required NotificationCounts current,
  }) {
    return ActivitiesDiff(
      previous: previous,
      current: current,
      increasedBy: NotificationCounts(
        submissions: _positiveDifference(
          previous.submissions,
          current.submissions,
        ),
        watches: _positiveDifference(previous.watches, current.watches),
        comments: _positiveDifference(previous.comments, current.comments),
        favorites: _positiveDifference(previous.favorites, current.favorites),
        journals: _positiveDifference(previous.journals, current.journals),
        notes: _positiveDifference(previous.notes, current.notes),
      ),
    );
  }

  ActivityNotificationDecision notificationDecision({
    required ActivitiesDiff diff,
    required bool submissionsEnabled,
    required bool watchesEnabled,
    required bool commentsEnabled,
    required bool favoritesEnabled,
    required bool journalsEnabled,
    required bool notesEnabled,
  }) {
    return ActivityNotificationDecision(
      increasedBy: NotificationCounts(
        submissions:
            submissionsEnabled ? diff.increasedBy.submissions : 0,
        watches: watchesEnabled ? diff.increasedBy.watches : 0,
        comments: commentsEnabled ? diff.increasedBy.comments : 0,
        favorites: favoritesEnabled ? diff.increasedBy.favorites : 0,
        journals: journalsEnabled ? diff.increasedBy.journals : 0,
        notes: notesEnabled ? diff.increasedBy.notes : 0,
      ),
    );
  }

  int _positiveDifference(int previous, int current) {
    return current > previous ? current - previous : 0;
  }
}

class ActivitiesDiff {
  const ActivitiesDiff({
    required this.previous,
    required this.current,
    required this.increasedBy,
  });

  final NotificationCounts previous;
  final NotificationCounts current;
  final NotificationCounts increasedBy;

  bool get hasAnyIncrease =>
      increasedBy.submissions > 0 ||
      increasedBy.watches > 0 ||
      increasedBy.comments > 0 ||
      increasedBy.favorites > 0 ||
      increasedBy.journals > 0 ||
      increasedBy.notes > 0;
}

class ActivityNotificationDecision {
  const ActivityNotificationDecision({required this.increasedBy});

  final NotificationCounts increasedBy;

  bool get shouldNotify =>
      increasedBy.submissions > 0 ||
      increasedBy.watches > 0 ||
      increasedBy.comments > 0 ||
      increasedBy.favorites > 0 ||
      increasedBy.journals > 0 ||
      increasedBy.notes > 0;
}
