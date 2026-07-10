String? buildAbsoluteFaUrl(String? href) {
  if (href == null) return null;
  final normalized = href.trim();
  if (normalized.isEmpty) return null;
  if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
    return normalized;
  }
  if (normalized.startsWith('//')) return 'https:$normalized';
  if (normalized.startsWith('/')) {
    return 'https://www.furaffinity.net$normalized';
  }
  return 'https://www.furaffinity.net/$normalized';
}

String buildFaJournalUrl(String journalId) {
  return 'https://www.furaffinity.net/journal/$journalId/';
}
