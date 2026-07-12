import 'package:FANotifier/features/search/data/search_image_parser.dart';
import 'package:FANotifier/features/search/data/search_image_service.dart';
import 'package:FANotifier/features/search/domain/search_repository.dart';

class SearchRepositoryImpl implements SearchRepository {
  SearchRepositoryImpl({SearchImageService? imageService})
      : _imageService = imageService ?? SearchImageService();

  final SearchImageService _imageService;

  @override
  Future<List<Map<String, dynamic>>> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required String searchQuery,
    required String cookieHeader,
  }) {
    return _imageService.fetchImages(
      pageNumber: pageNumber,
      selectedFilters: selectedFilters,
      searchQuery: searchQuery,
      cookieHeader: cookieHeader,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> parseRecoveredHtml(String html) {
    return parseSearchImageHtml(html);
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
}
