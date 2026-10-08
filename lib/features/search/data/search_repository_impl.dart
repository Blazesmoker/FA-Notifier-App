import 'dart:async';

import 'package:fanotifier/features/search/data/search_image_parser.dart';
import 'package:fanotifier/features/search/data/search_image_service.dart';
import 'package:fanotifier/features/search/domain/search_repository.dart';
import 'package:fanotifier/features/search/domain/search_page_data.dart';
import 'package:fanotifier/shared/fa/data/fa_filter_options_cache.dart';
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';

class SearchRepositoryImpl implements SearchRepository {
  SearchRepositoryImpl({SearchImageService? imageService})
      : _imageService = imageService ?? SearchImageService();

  final SearchImageService _imageService;
  final _filterOptions = FaFilterOptionsCache();

  @override
  Future<SearchPageData> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required String searchQuery,
    required FutureOr<String> cookieHeader,
    bool Function()? isCancelled,
  }) {
    return _filterOptions.capture(
      (cancelled) async => _imageService.fetchImages(
        pageNumber: pageNumber,
        selectedFilters: selectedFilters,
        searchQuery: searchQuery,
        cookieHeader: await cookieHeader,
        isCancelled: cancelled,
      ),
      (page) => page.filterOptions,
      isCancelled: isCancelled,
    );
  }

  @override
  Future<SearchPageData> parseRecoveredHtml(String html) {
    return _filterOptions.capture(
      (_) => parseSearchImageHtml(html),
      (page) => page.filterOptions,
    );
  }

  @override
  FaFilterOptions? get filterOptions => _filterOptions.current;

  @override
  Stream<FaFilterOptions> get filterOptionsChanges => _filterOptions.changes;

  @override
  Future<FaFilterOptions> fetchFilterOptions({
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  }) {
    return _filterOptions.requireOptions(
      load: (cancelled) => _imageService.fetchFilterOptions(
        selectedFilters: selectedFilters,
        sfwEnabled: sfwEnabled,
        isCancelled: cancelled,
      ),
    );
  }

  @override
  void clearFilterOptions() => _filterOptions.clear();

  @override
  void dispose() => _filterOptions.dispose();

  @override
  Future<String> buildCookieHeader({
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  }) {
    return _imageService.buildCookieHeader(
      selectedFilters: selectedFilters,
      sfwEnabled: sfwEnabled,
    );
  }
}
