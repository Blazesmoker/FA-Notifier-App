class HomeLoginWebViewAssets {
  const HomeLoginWebViewAssets({
    required this.initialHtml,
    required this.outerHtmlScript,
    required this.css,
  });

  final String initialHtml;
  final String outerHtmlScript;
  final String css;
}

abstract interface class HomeLoginLoadSlot {
  Future<void> recordLoadStart();
}

abstract interface class HomeLoginWebViewSupport {
  HomeLoginWebViewAssets get assets;

  String get loginUrl;

  Future<HomeLoginLoadSlot> waitForAvailableLoadSlot();

  bool isPasswordRecoveryUrl(Uri? uri);

  bool isLoginUrl(String? url);

  bool isAuthenticatedHomeUrl(String? url);

  bool hasLoggedInHomeElement(String? html);
}
