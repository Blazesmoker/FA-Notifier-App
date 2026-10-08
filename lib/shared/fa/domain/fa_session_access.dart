abstract interface class FaSessionAccess {
  String get userAgent;

  int get verifiedGeneration;

  Stream<int> get verifiedSessions;

  Future<void> synchronizeWebViewSession();
}
