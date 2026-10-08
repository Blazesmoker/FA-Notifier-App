import 'dart:async';

import 'package:fanotifier/features/search/domain/search_page_data.dart';
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';

abstract interface class SearchRepository {
  Future<SearchPageData> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required String searchQuery,
    required FutureOr<String> cookieHeader,
    bool Function()? isCancelled,
  });

  Future<SearchPageData> parseRecoveredHtml(String html);

  Future<String> buildCookieHeader({
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  });

  FaFilterOptions? get filterOptions;
  Stream<FaFilterOptions> get filterOptionsChanges;
  Future<FaFilterOptions> fetchFilterOptions({
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  });
  void clearFilterOptions();
  void dispose();
}
