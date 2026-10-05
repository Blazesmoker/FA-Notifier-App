import 'package:fanotifier/features/ads/data/fa_ads_repository_impl.dart';
import 'package:fanotifier/features/ads/data/fa_webview_ad_gateway_impl.dart';
import 'package:fanotifier/features/ads/domain/fa_ads_repository.dart';
import 'package:fanotifier/features/ads/domain/fa_webview_ad_gateway.dart';

class AdsFeature {
  const AdsFeature._();

  static FaAdsRepository createRepository() => FaAdsRepositoryImpl();

  static FaWebViewAdGateway createWebViewAdGateway() =>
      const FaWebViewAdGatewayImpl();
}
