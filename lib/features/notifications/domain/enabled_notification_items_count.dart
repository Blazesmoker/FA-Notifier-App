import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/shared/fa/domain/notification_counts.dart';

int enabledNotificationItemsCount({
  required Iterable<NotificationSection> sections,
  required bool watchersEnabled,
  required bool journalsEnabled,
  required bool commentsEnabled,
  required bool favoritesEnabled,
  required bool shoutsEnabled,
  NotificationCounts? counts,
}) {
  var visible = 0;
  for (final section in sections) {
    final title = section.title;
    final count = section.items.length;
    if (title.contains('Watches') && watchersEnabled && counts == null) {
      visible += count;
    }
    if (title.contains('Journals') && journalsEnabled && counts == null) {
      visible += count;
    }
    if (title.contains('Submission Comments') && commentsEnabled) {
      visible += count;
    }
    if (title.contains('Journal Comments') && commentsEnabled) {
      visible += count;
    }
    if (title.contains('Favorites') && favoritesEnabled && counts == null) {
      visible += count;
    }
    if (title.contains('Shouts') && shoutsEnabled) visible += count;
  }
  if (counts != null) {
    if (watchersEnabled) {
      visible += counts.watches;
    }
    if (journalsEnabled) {
      visible += counts.journals;
    }
    if (favoritesEnabled) {
      visible += counts.favorites;
    }
  }
  return visible;
}
