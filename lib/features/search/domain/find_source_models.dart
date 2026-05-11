class IndexMapping {
  final String? link;
  final bool isHeader;

  IndexMapping({this.link, this.isHeader = false});
}

class FindSourceError implements Exception {
  final String message;

  const FindSourceError(this.message);
}

class FindSourceSearchResult {
  const FindSourceSearchResult({
    required this.faAuthorLinks,
    required this.faPostLinks,
    required this.e621PostLinks,
    required this.combinedResults,
    required this.accuracy,
  });

  final List<String> faAuthorLinks;
  final List<String> faPostLinks;
  final List<String> e621PostLinks;
  final List<String> combinedResults;
  final double? accuracy;
}
