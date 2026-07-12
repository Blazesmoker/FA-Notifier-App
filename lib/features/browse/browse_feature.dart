import 'package:FANotifier/features/browse/data/browse_repository_impl.dart';
import 'package:FANotifier/features/browse/domain/browse_repository.dart';

class BrowseFeature {
  const BrowseFeature._();

  static BrowseRepository createRepository() {
    return BrowseRepositoryImpl();
  }
}
