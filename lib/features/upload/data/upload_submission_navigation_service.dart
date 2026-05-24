class UploadSubmissionNavigationService {
  const UploadSubmissionNavigationService();

  String get initialUrl => 'https://www.furaffinity.net/submit/';

  String get finalizeUrl => 'https://www.furaffinity.net/submit/finalize/';

  bool isFinalizeUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return false;
    return parsed.path.startsWith('/submit/finalize');
  }

  bool isInitialSubmitUrl(String url) {
    return url.startsWith(initialUrl);
  }

  int? extractSubmissionId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'view') {
        final idStr = uri.pathSegments[1];
        return int.tryParse(idStr);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
