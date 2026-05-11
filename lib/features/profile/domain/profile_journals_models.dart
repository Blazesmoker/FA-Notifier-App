class ProfileJournalsPageData {
  const ProfileJournalsPageData({
    required this.journals,
    required this.hasMore,
  });

  final List<Map<String, dynamic>> journals;
  final bool hasMore;
}

class ProfileJournalsParseResult {
  final List<Map<String, dynamic>> journals;
  final bool hasMore;

  const ProfileJournalsParseResult({
    required this.journals,
    required this.hasMore,
  });
}
