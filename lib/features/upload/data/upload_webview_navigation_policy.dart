class UploadWebViewNavigationPolicy {
  const UploadWebViewNavigationPolicy();

  static const Set<String> _blockedIosHosts = <String>{
    'www15.smartadserver.com',
    'securepubads.g.doubleclick.net',
    'cdn.playwire.com',
    'z.moatads.com',
    'pagead2.googlesyndication.com',
    'cdn.intergient.com',
    'cdn.intergi.com',
    'config.playwire.com',
  };

  bool shouldBlockIosHost(String host) {
    return _blockedIosHosts.contains(host);
  }
}
