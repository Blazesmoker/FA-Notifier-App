import 'package:fanotifier/features/browse/domain/browse_page_data.dart';
import 'package:fanotifier/features/browse/data/browse_filter_options_service.dart';
import 'package:fanotifier/features/browse/data/browse_image_parser.dart';
import 'package:fanotifier/features/browse/data/browse_image_service.dart';
import 'package:fanotifier/features/browse/domain/browse_repository.dart';

class BrowseRepositoryImpl implements BrowseRepository {
  BrowseRepositoryImpl({BrowseImageService? imageService})
      : _imageService = imageService ?? BrowseImageService();

  final BrowseImageService _imageService;

  @override
  Future<BrowsePageData> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
    bool Function()? isCancelled,
  }) {
    return _imageService.fetchImages(
      pageNumber: pageNumber,
      selectedFilters: selectedFilters,
      sfwEnabled: sfwEnabled,
      isCancelled: isCancelled,
    );
  }

  @override
  Future<BrowsePageData> parseRecoveredHtml(
    String html, {
    required Uri documentUri,
    required bool effectiveSfwEnabled,
  }) async {
    final parsed = await parseBrowsePageHtml(
      html: html,
      documentUri: documentUri,
      sfwEnabled: effectiveSfwEnabled,
      recovered: true,
    );
    return parsed.page;
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
  Future<Map<String, List<Map<String, String>>>> fetchFilterOptions() {
    return fetchBrowseFilterOptions();
  }
}
