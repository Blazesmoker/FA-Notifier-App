import 'package:fanotifier/features/browse/domain/browse_page_data.dart';
import 'package:fanotifier/features/browse/data/browse_image_parser.dart';
import 'package:fanotifier/features/browse/data/browse_image_service.dart';
import 'package:fanotifier/features/browse/domain/browse_repository.dart';
import 'package:fanotifier/shared/fa/data/fa_filter_options_cache.dart';
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';

class BrowseRepositoryImpl implements BrowseRepository {
  BrowseRepositoryImpl({BrowseImageService? imageService})
      : _imageService = imageService ?? BrowseImageService();

  final BrowseImageService _imageService;
  final _filterOptions = FaFilterOptionsCache();

  @override
  Future<BrowsePageData> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
    bool Function()? isCancelled,
  }) {
    return _filterOptions.capture(
      (cancelled) => _imageService.fetchImages(
        pageNumber: pageNumber,
        selectedFilters: selectedFilters,
        sfwEnabled: sfwEnabled,
        isCancelled: cancelled,
      ),
      (page) => page.filterOptions,
      isCancelled: isCancelled,
    );
  }

  @override
  Future<BrowsePageData> parseRecoveredHtml(
    String html, {
    required Uri documentUri,
    required bool effectiveSfwEnabled,
  }) {
    return _filterOptions.capture(
      (_) async {
        final parsed = await parseBrowsePageHtml(
          html: html,
          documentUri: documentUri,
          sfwEnabled: effectiveSfwEnabled,
          recovered: true,
        );
        return parsed.page;
      },
      (page) => page.filterOptions,
    );
  }

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

  @override
  FaFilterOptions? get filterOptions => _filterOptions.current;

  @override
  Stream<FaFilterOptions> get filterOptionsChanges => _filterOptions.changes;

  @override
  Future<FaFilterOptions> fetchFilterOptions() => _filterOptions.requireOptions();

  @override
  void clearFilterOptions() => _filterOptions.clear();

  @override
  void dispose() => _filterOptions.dispose();
}
