class NotificationTabBadgeValue {
  const NotificationTabBadgeValue({
    required this.rawCount,
    required this.displayText,
  });

  final int rawCount;
  final String displayText;
}

NotificationTabBadgeValue notificationTabBadgeValue({
  required String sectionTitle,
  required int itemCount,
  required Map<String, int> messageBarCounts,
}) {
  final normalizedTitle = sectionTitle.toLowerCase();
  String? typeKey;
  if (normalizedTitle.contains('watch')) {
    typeKey = 'W';
  } else if (normalizedTitle.contains('favorite')) {
    typeKey = 'F';
  } else if (normalizedTitle.contains('journal') &&
      !normalizedTitle.contains('comment')) {
    typeKey = 'J';
  }

  final rawCount = typeKey != null && messageBarCounts.containsKey(typeKey)
      ? messageBarCounts[typeKey]!
      : itemCount;
  final displayText = normalizedTitle.contains('comment') ||
          normalizedTitle.contains('shout')
      ? rawCount >= 30
          ? '30+'
          : '$rawCount'
      : '$rawCount';
  return NotificationTabBadgeValue(
    rawCount: rawCount,
    displayText: displayText,
  );
}
