abstract interface class BrowseRepository {
  Future<List<Map<String, dynamic>>> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  });

  Future<List<Map<String, dynamic>>> parseRecoveredHtml(String html);

  Future<String> buildCookieHeader({
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  });

  Future<Map<String, List<Map<String, String>>>> fetchFilterOptions();
}
