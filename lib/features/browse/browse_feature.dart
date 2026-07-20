import 'package:fanotifier/features/browse/data/browse_repository_impl.dart';
import 'package:fanotifier/features/browse/domain/browse_repository.dart';

class BrowseFeature {
  const BrowseFeature._();

  static BrowseRepository createRepository() {
    return BrowseRepositoryImpl();
  }
}
