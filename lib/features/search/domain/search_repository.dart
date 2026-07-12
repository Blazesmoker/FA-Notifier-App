abstract interface class SearchRepository {
  Future<List<Map<String, dynamic>>> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required String searchQuery,
    required String cookieHeader,
  });

  Future<List<Map<String, dynamic>>> parseRecoveredHtml(String html);

  Future<String> buildCookieHeader({
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  });
}
