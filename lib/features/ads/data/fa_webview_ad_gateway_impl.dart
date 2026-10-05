import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/ads/data/fa_ad_parser.dart';
import 'package:fanotifier/features/ads/data/fa_webview_ad_scripts.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/features/ads/domain/fa_webview_ad_gateway.dart';

class FaWebViewAdGatewayImpl implements FaWebViewAdGateway {
  const FaWebViewAdGatewayImpl();

  static const _documentPathPattern =
      r'^/(?:submit(?:/(?:upload|finalize))?/?|controls/journal(?:/.*)?|controls/submissions/(?:changeinfo|changesubmission|changethumbnail)/[0-9]+/?)$';

  @override
  String get tapHandlerScript => buildFaWebViewAdTapHandlerScript(
        documentPathPattern: _documentPathPattern,
      );

  @override
  bool isSupportedDocument(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'www.furaffinity.net' || uri.host == 'furaffinity.net') &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      RegExp(_documentPathPattern).hasMatch(uri.path);

  @override
  bool isTrackingClick(Uri uri) =>
      isFaAdEndpoint(uri, 'cl.php') || isFaAdEndpoint(uri, 'ck.php');

  @override
  Future<FaAdPageContext> readPageContext(Uri documentUri) async {
    final cookie = await CookieManager.instance().getCookie(
      url: WebUri(documentUri.toString()),
      name: 'sfw',
    );
    final value = cookie?.value.toString();
    final sfwEnabled = value == '1'
        ? true
        : value == '0'
            ? false
            : await const SfwModePreference().loadSfwEnabled();
    return FaAdPageContext(
      documentUri: documentUri,
      sfwEnabled: sfwEnabled,
    );
  }
}
