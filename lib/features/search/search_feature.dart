import 'package:FANotifier/features/search/data/find_source_repository_impl.dart';
import 'package:FANotifier/features/search/data/search_repository_impl.dart';
import 'package:FANotifier/features/search/domain/find_source_repository.dart';
import 'package:FANotifier/features/search/domain/search_repository.dart';

class SearchFeature {
  const SearchFeature._();

  static SearchRepository createRepository() {
    return SearchRepositoryImpl();
  }

  static FindSourceRepository createFindSourceRepository() {
    return FindSourceRepositoryImpl();
  }
}
