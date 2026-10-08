abstract final class FaPageSettings {
  static const pageKey = 'page';
  static const perPageKey = 'perpage';
  static const firstPage = 1;
  static const defaultPerPage = 72;

  static int? positiveInteger(String? value) {
    final number = int.tryParse(value?.trim() ?? '');
    if (number == null || number < firstPage) {
      return null;
    }
    return number;
  }

  static int startingPage(Map<String, String> filters) =>
      positiveInteger(filters[pageKey]) ?? firstPage;

  static String resultsPerPage(Map<String, String> filters) =>
      (positiveInteger(filters[perPageKey]) ?? defaultPerPage).toString();
}
