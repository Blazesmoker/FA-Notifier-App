import 'package:fanotifier/features/home/data/home_login_html_detector.dart'
    as home_login_html;
import 'package:fanotifier/features/home/data/home_login_webview_load_throttle.dart';
import 'package:fanotifier/features/home/data/home_login_webview_navigation_policy.dart';
import 'package:fanotifier/features/home/data/home_login_webview_scripts.dart';
import 'package:fanotifier/features/home/domain/home_login_webview_support.dart';

class HomeLoginWebViewSupportImpl implements HomeLoginWebViewSupport {
  const HomeLoginWebViewSupportImpl({
    HomeLoginWebViewLoadThrottle loadThrottle =
        const HomeLoginWebViewLoadThrottle(),
    HomeLoginWebViewNavigationPolicy navigationPolicy =
        const HomeLoginWebViewNavigationPolicy(),
  })  : _loadThrottle = loadThrottle,
        _navigationPolicy = navigationPolicy;

  final HomeLoginWebViewLoadThrottle _loadThrottle;
  final HomeLoginWebViewNavigationPolicy _navigationPolicy;

  @override
  HomeLoginWebViewAssets get assets => const HomeLoginWebViewAssets(
        initialHtml: homeLoginInitialHtml,
        outerHtmlScript: homeLoginOuterHtmlScript,
        css: homeLoginCss,
      );

  @override
  String get loginUrl => HomeLoginWebViewNavigationPolicy.loginUrl;

  @override
  Future<HomeLoginLoadSlot> waitForAvailableLoadSlot() {
    return _loadThrottle.waitForAvailableSlot();
  }

  @override
  bool isPasswordRecoveryUrl(Uri? uri) {
    return _navigationPolicy.isPasswordRecoveryUrl(uri);
  }

  @override
  bool isLoginUrl(String? url) {
    return _navigationPolicy.isLoginUrl(url);
  }

  @override
  bool isAuthenticatedHomeUrl(String? url) {
    return _navigationPolicy.isAuthenticatedHomeUrl(url);
  }

  @override
  bool hasLoggedInHomeElement(String? html) {
    return home_login_html.hasLoggedInHomeElement(html);
  }
}
