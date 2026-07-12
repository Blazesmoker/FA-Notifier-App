import 'package:FANotifier/core/fa/fa_webview_cookie_service.dart';
import 'package:FANotifier/features/submissions/data/edit_submission_navigation_service.dart';
import 'package:FANotifier/features/submissions/data/edit_submission_webview_scripts.dart'
    as scripts;
import 'package:FANotifier/features/submissions/domain/edit_submission_page_repository.dart';

class EditSubmissionPageRepositoryImpl
    implements EditSubmissionPageRepository {
  const EditSubmissionPageRepositoryImpl({
    EditSubmissionNavigationService navigationService =
        const EditSubmissionNavigationService(),
    FAWebViewCookieService webViewCookieService =
        const FAWebViewCookieService(),
  })  : _navigationService = navigationService,
        _webViewCookieService = webViewCookieService;

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
