import 'package:fanotifier/features/ads/domain/fa_ads_repository.dart';
import 'package:fanotifier/features/browse/data/browse_image_service.dart';
import 'package:fanotifier/features/browse/data/browse_repository_impl.dart';
import 'package:fanotifier/features/browse/domain/browse_repository.dart';

class BrowseFeature {
  const BrowseFeature._();

  static BrowseRepository createRepository({required FaAdsRepository adsRepository}) {
    return BrowseRepositoryImpl(
      imageService: BrowseImageService(onDocumentCookies: adsRepository.acceptDocumentCookies),
    );
  }
}
