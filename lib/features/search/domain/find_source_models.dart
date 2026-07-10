class IndexMapping {
  final String? link;
  final bool isHeader;

  IndexMapping({this.link, this.isHeader = false});
}

int getFindSourceResultItemCount({
  required List<String> faAuthorLinks,
  required List<String> faPostLinks,
  required List<String> e621PostLinks,
}) {
  var count = 0;
  final hasFa = faAuthorLinks.isNotEmpty || faPostLinks.isNotEmpty;
  if (hasFa) {
    count += 1;
    count += faAuthorLinks.length;
    count += faPostLinks.length;
  }
  if (e621PostLinks.isNotEmpty) {
    count += 1 + e621PostLinks.length;
  }
  return count;
}

IndexMapping? getFindSourceResultItem({
  required int index,
  required List<String> faAuthorLinks,
  required List<String> faPostLinks,
  required List<String> e621PostLinks,
}) {
  var currentIndex = index;

  final hasFa = faAuthorLinks.isNotEmpty || faPostLinks.isNotEmpty;
  if (hasFa) {
    if (currentIndex == 0) {
      return IndexMapping(link: 'Fur Affinity.net', isHeader: true);
    }
    currentIndex -= 1;
    if (currentIndex < faAuthorLinks.length) {
      return IndexMapping(link: faAuthorLinks[currentIndex]);
    }
    currentIndex -= faAuthorLinks.length;
    if (currentIndex < faPostLinks.length) {
      return IndexMapping(link: faPostLinks[currentIndex]);
    }
    currentIndex -= faPostLinks.length;
  }

  if (e621PostLinks.isNotEmpty) {
    if (currentIndex == 0) {
      return IndexMapping(link: 'e621.net', isHeader: true);
    }
    currentIndex -= 1;
    if (currentIndex < e621PostLinks.length) {
      return IndexMapping(link: e621PostLinks[currentIndex]);
    }
  }

  return null;
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
