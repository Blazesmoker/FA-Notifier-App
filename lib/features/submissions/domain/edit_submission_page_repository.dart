abstract interface class EditSubmissionPageRepository {
  Future<void> prepareWebViewSession();

  bool isUpdateSubmissionUrl(String url);

  bool isSubmissionViewUrl(String url);

  String buildBaseScript();

  String buildMoveSubmissionFileCellScript();

  String buildWrapSelectionScript(String tag);
}
