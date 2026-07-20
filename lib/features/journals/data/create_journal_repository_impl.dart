import 'package:fanotifier/core/fa/fa_webview_cookie_service.dart';
import 'package:fanotifier/features/journals/data/create_journal_service.dart';
import 'package:fanotifier/features/journals/data/create_journal_webview_scripts.dart'
    as scripts;
import 'package:fanotifier/features/journals/domain/create_journal_repository.dart';

class CreateJournalRepositoryImpl implements CreateJournalRepository {
  const CreateJournalRepositoryImpl({
    CreateJournalService service = const CreateJournalService(),
    FAWebViewCookieService webViewCookieService =
        const FAWebViewCookieService(),
  })  : _service = service,
        _webViewCookieService = webViewCookieService;

  final CreateJournalService _service;
  final FAWebViewCookieService _webViewCookieService;

  @override
  Future<void> prepareWebViewSession() {
    return _webViewCookieService.setCookies();
  }

  @override
  String buildInitialUrl(String? uniqueNumber) {
    return _service.buildInitialUrl(uniqueNumber);
  }

  @override
  bool isJournalFinalizeUrl(String? url) {
    return _service.isJournalFinalizeUrl(url);
  }

  @override
  bool isEditorPage(String? url) {
    return _service.isEditorPage(url);
  }

  @override
  bool shouldInjectEditorAssets({
    required String currentUrl,
    required String initialUrl,
  }) {
    return currentUrl.startsWith(initialUrl);
  }

  @override
  String? extractJournalId(String url) {
    return _service.extractJournalId(url);
  }

  @override
  String buildFullJournalUrl(String path) {
    return _service.buildFullJournalUrl(path);
  }

  @override
  String buildFindCreatedJournalPathScript() {
    return scripts.buildFindCreatedJournalPathScript();
  }

  @override
  String buildJournalFormInjectionScript() {
    return scripts.buildJournalFormInjectionScript();
  }

  @override
  String buildJournalWrapSelectionScript(String tag) {
    return scripts.buildJournalWrapSelectionScript(tag);
  }
}
