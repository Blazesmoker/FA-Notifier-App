import 'package:FANotifier/features/notifications/domain/fa_notification_models.dart';

List<Shout> notificationShoutsFromSections(
  List<NotificationSection> sections,
) {
  try {
    final index = sections.indexWhere(
      (section) => section.title.toLowerCase().contains('shouts'),
    );
    if (index == -1) return const <Shout>[];
    final items = sections[index].items;
    if (items.isEmpty) return const <Shout>[];
    return items.map((item) {
      return Shout(
        id: item.id,
        nickname: item.username ?? '',
        nicknameLink: item.linkUsername ?? '',
        postedTitle: item.fullDate,
        avatarUrl: item.avatarUrl ?? '',
        postedAgo: item.date,
        textContent: item.content,
        isRemoved: item.content
            .toLowerCase()
            .contains('shout has been removed'),
        isChecked: item.isChecked,
      );
    }).toList();
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
