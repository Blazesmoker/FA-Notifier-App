bool looksLikeUnavailableJournal({
  required String? title,
  required String? descriptionHtml,
  required String? rawDate,
}) {
  final titleLower = (title ?? '').toLowerCase();
  final descriptionLower = (descriptionHtml ?? '').toLowerCase();
  final rawDateLower = (rawDate ?? '').toLowerCase();
  return titleLower.contains('system error') ||
      descriptionLower.contains('not in our database') ||
      descriptionLower.contains('this submission does not exist') ||
      titleLower.contains('not in our database') ||
      rawDateLower.contains('not in our database');
}
