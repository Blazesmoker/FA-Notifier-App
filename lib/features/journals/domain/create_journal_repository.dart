abstract interface class CreateJournalRepository {
  Future<void> prepareWebViewSession();

  String buildInitialUrl(String? uniqueNumber);

  bool isJournalFinalizeUrl(String? url);

  bool isEditorPage(String? url);

  bool shouldInjectEditorAssets({
    required String currentUrl,
    required String initialUrl,
  });

  String? extractJournalId(String url);

  String buildFullJournalUrl(String path);

  String buildFindCreatedJournalPathScript();

  String buildJournalFormInjectionScript();

  String buildJournalWrapSelectionScript(String tag);
}
