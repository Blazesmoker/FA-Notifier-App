import 'package:FANotifier/features/browse/data/browse_filter_options_service.dart';
import 'package:FANotifier/features/browse/data/browse_image_parser.dart';
import 'package:FANotifier/features/browse/data/browse_image_service.dart';
import 'package:FANotifier/features/browse/domain/browse_repository.dart';

class BrowseRepositoryImpl implements BrowseRepository {
  BrowseRepositoryImpl({BrowseImageService? imageService})
      : _imageService = imageService ?? BrowseImageService();

  final BrowseImageService _imageService;

  @override
  Future<List<Map<String, dynamic>>> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  }) {
    return _imageService.fetchImages(
      pageNumber: pageNumber,
      selectedFilters: selectedFilters,
      sfwEnabled: sfwEnabled,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> parseRecoveredHtml(String html) {
    return parseBrowseImageHtml(html);
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
