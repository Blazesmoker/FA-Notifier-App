import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';

abstract interface class FaWebViewAdGateway {
  String get tapHandlerScript;

  bool isSupportedDocument(Uri uri);

  bool isTrackingClick(Uri uri);

  Future<FaAdPageContext> readPageContext(Uri documentUri);
}
