import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class HomeLoginWebViewNavigationPolicy {
  const HomeLoginWebViewNavigationPolicy();

  static const String _passwordRecoveryPath = '/lostpw/';

  bool isPasswordRecoveryUrl(WebUri? uri) {
    return uri != null &&
        uri.host.contains('furaffinity.net') &&
        uri.path.contains(_passwordRecoveryPath);
  }
}
