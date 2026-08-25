import 'package:fanotifier/core/fa/fa_webview_cookie_service.dart';
import 'package:fanotifier/features/submissions/data/edit_submission_navigation_service.dart';
import 'package:fanotifier/features/submissions/data/edit_submission_webview_scripts.dart'
    as scripts;
import 'package:fanotifier/features/submissions/domain/edit_submission_page_repository.dart';

class EditSubmissionPageRepositoryImpl
    implements EditSubmissionPageRepository {
  const EditSubmissionPageRepositoryImpl({
    this._navigationService = const EditSubmissionNavigationService(),
    this._webViewCookieService = const FAWebViewCookieService(),
  });

  final EditSubmissionNavigationService _navigationService;
  final FAWebViewCookieService _webViewCookieService;

  @override
  Future<void> prepareWebViewSession() {
    return _webViewCookieService.setCookies();
  }

  @override
  bool isUpdateSubmissionUrl(String url) {
    return _navigationService.isUpdateSubmissionUrl(url);
  }

  @override
  String? updateFileInputName(String url) {
    return _navigationService.updateFileInputName(url);
  }

  @override
  bool isSubmissionViewUrl(String url) {
    return _navigationService.isSubmissionViewUrl(url);
  }

  @override
  String buildBaseScript() {
    return scripts.buildEditSubmissionBaseScript();
  }

  @override
  String buildMoveSubmissionFileCellScript() {
    return scripts.buildMoveSubmissionFileCellScript();
  }

  @override
  String buildWrapSelectionScript(String tag) {
    return scripts.buildWrapSelectionScript(tag);
  }
}
