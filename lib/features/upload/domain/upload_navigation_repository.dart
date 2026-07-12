abstract interface class UploadNavigationRepository {
  String get initialUrl;

  String get finalizeUrl;

  bool isFinalizeUrl(String url);

  bool isInitialSubmitUrl(String url);

  bool isUploadSuccessfulUrl(String url);

  int? extractSubmissionId(String url);

  bool shouldBlockIosHost(String host);
}
