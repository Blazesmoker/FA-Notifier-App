class CreateJournalService {
  const CreateJournalService();

  static const String finalizeUrlPrefix = 'https://www.furaffinity.net/journal/';

  String buildInitialUrl(String? uniqueNumber) {
    if (uniqueNumber != null) {
      return 'https://www.furaffinity.net/controls/journal/1/$uniqueNumber/';
    }
    return 'https://www.furaffinity.net/controls/journal/';
  }

  bool isJournalFinalizeUrl(String? url) {
    return url != null && url.startsWith(finalizeUrlPrefix);
  }

  bool isEditorPage(String? url) {
    if (url == null) return false;
    return url.contains('/controls/journal');
  }

  String? extractJournalId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'journal') {
        return uri.pathSegments[1];
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String buildFullJournalUrl(String path) {
    return 'https://www.furaffinity.net$path';
  }
}
