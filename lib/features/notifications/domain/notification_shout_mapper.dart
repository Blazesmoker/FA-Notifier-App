import 'package:fanotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:fanotifier/features/notifications/domain/notification_shout_merge_policy.dart';

const NotificationShoutMergePolicy _shoutMergePolicy =
    NotificationShoutMergePolicy();

List<Shout> notificationShoutsFromSections(
  List<NotificationSection> sections,
) {
  try {
    final index = _shoutMergePolicy.shoutSectionIndex(sections);
    if (index == -1) return const <Shout>[];
    final items = sections[index].items;
    if (items.isEmpty) return const <Shout>[];
    return _shoutMergePolicy.shoutsFromItems(items);
  } catch (_) {
    return const <Shout>[];
  }
}

List<Shout> deduplicateNotificationShouts(List<Shout> shouts) {
  final unique = <String, Shout>{};
  for (final shout in shouts) {
    unique[shout.id] = shout;
  }
  return unique.values.toList();
}
