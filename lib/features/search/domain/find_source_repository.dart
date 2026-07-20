import 'package:fanotifier/features/search/domain/find_source_models.dart';

abstract interface class FindSourceRepository {
  Future<String?> pickImagePath();

  Future<String> hashImagePath(String imagePath);

  Future<FindSourceSearchResult> searchSources(String imagePath);
}
