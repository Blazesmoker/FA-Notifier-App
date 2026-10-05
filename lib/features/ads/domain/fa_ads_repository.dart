import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';

abstract interface class FaAdsRepository {
  Future<void> acceptDocumentCookies({
    required Uri documentUri,
    required String? setCookieHeader,
  });

  Future<FaAdDelivery> fetchDelivery({
    required FaAdPageMetadata page,
    required FaAdLayout layout,
    required FaAdCancellation cancellation,
    required bool Function() canStart,
  });

  Future<FaAdImage> fetchImage({
    required FaAdCreative creative,
    required FaAdPageMetadata page,
    required FaAdCancellation cancellation,
  });

  Future<void> registerImpression({
    required FaAdCreative creative,
    required FaAdPageMetadata page,
    required FaAdCancellation cancellation,
    required bool Function() canStart,
  });

  Future<Uri> resolveClick({
    required FaAdCreative creative,
    required FaAdPageMetadata page,
    required FaAdCancellation cancellation,
    required bool Function() canStart,
  });

  Future<Uri> resolveClickUrl({
    required Uri clickUri,
    required FaAdPageContext page,
    required FaAdCancellation cancellation,
    required bool Function() canStart,
  });

  Future<void> resetSession();

  void dispose();
}
