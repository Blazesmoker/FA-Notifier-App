import 'package:fanotifier/features/browse/domain/browse_page_data.dart';
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';

abstract interface class BrowseRepository {
  Future<BrowsePageData> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
    bool Function()? isCancelled,
  });

  Future<BrowsePageData> parseRecoveredHtml(
    String html, {
    required Uri documentUri,
    required bool effectiveSfwEnabled,
  });

  Future<String> buildCookieHeader({
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  });

  FaFilterOptions? get filterOptions;
  Stream<FaFilterOptions> get filterOptionsChanges;
  Future<FaFilterOptions> fetchFilterOptions();
  void clearFilterOptions();
  void dispose();
}
