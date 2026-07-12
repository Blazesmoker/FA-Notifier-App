class HomeLoginWebViewNavigationPolicy {
  const HomeLoginWebViewNavigationPolicy();

  static const String loginUrl = 'https://www.furaffinity.net/login';
  static const String _homeUrl = 'https://www.furaffinity.net';
  static const String _passwordRecoveryPath = '/lostpw/';

  bool isLoginUrl(String? url) {
    return url?.startsWith(loginUrl) == true;
  }

  bool isAuthenticatedHomeUrl(String? url) {
    return url?.startsWith('$_homeUrl/') == true || url == _homeUrl;
  }

  bool isPasswordRecoveryUrl(Uri? uri) {
    return uri != null &&
        uri.host.contains('furaffinity.net') &&
        uri.path.contains(_passwordRecoveryPath);
  }
}
