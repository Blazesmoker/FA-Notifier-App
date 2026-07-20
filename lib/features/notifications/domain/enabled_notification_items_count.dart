import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';

int enabledNotificationItemsCount({
  required Iterable<NotificationSection> sections,
  required bool watchersEnabled,
  required bool journalsEnabled,
  required bool commentsEnabled,
  required bool favoritesEnabled,
  required bool shoutsEnabled,
}) {
  var visible = 0;
  for (final section in sections) {
    final title = section.title;
    final count = section.items.length;
    if (title.contains('Watches') && watchersEnabled) visible += count;
    if (title.contains('Journals') && journalsEnabled) visible += count;
    if (title.contains('Submission Comments') && commentsEnabled) {
      visible += count;
    }
    if (title.contains('Journal Comments') && commentsEnabled) {
      visible += count;
    }
    if (title.contains('Favorites') && favoritesEnabled) visible += count;
    if (title.contains('Shouts') && shoutsEnabled) visible += count;
  }
  return visible;
}
