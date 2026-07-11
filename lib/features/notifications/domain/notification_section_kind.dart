enum NotificationSectionKind {
  watches,
  favorites,
  submissionComments,
  journalComments,
  shouts,
  journals,
  other,
}

NotificationSectionKind notificationSectionKindFromTitle(String title) {
  final normalized = title.toLowerCase();
  if (normalized.contains('watches')) {
    return NotificationSectionKind.watches;
  }
  if (normalized.contains('favorites')) {
    return NotificationSectionKind.favorites;
  }
  if (normalized.contains('submission comments')) {
    return NotificationSectionKind.submissionComments;
  }
  if (normalized.contains('journal comments')) {
    return NotificationSectionKind.journalComments;
  }
  if (normalized.contains('shouts')) {
    return NotificationSectionKind.shouts;
  }
  if (normalized.contains('journals')) {
    return NotificationSectionKind.journals;
  }
  return NotificationSectionKind.other;
}

bool isShoutsNotificationSectionTitle(String title) {
  return title.toLowerCase().contains('shouts');
}

int notificationSectionIndexForInitialTitle(
  Iterable<String> titles,
  String initialSection,
) {
  final normalized = initialSection.toLowerCase();
  var index = 0;
  for (final title in titles) {
    if (title.toLowerCase().contains(normalized)) return index;
    index++;
  }
  return -1;
}
