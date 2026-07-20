import 'package:fanotifier/features/notes/data/note_reply_webview_cookie_service.dart';
import 'package:fanotifier/features/notes/data/note_reply_webview_navigation_service.dart';
import 'package:fanotifier/features/notes/data/note_reply_webview_scripts.dart';
import 'package:fanotifier/features/notes/domain/note_reply_webview_gateway.dart';

class NoteReplyWebViewGatewayImpl implements NoteReplyWebViewGateway {
  const NoteReplyWebViewGatewayImpl({
    NoteReplyWebViewCookieService cookieService =
        const NoteReplyWebViewCookieService(),
    NoteReplyWebViewNavigationService navigationService =
        const NoteReplyWebViewNavigationService(),
  })  : _cookieService = cookieService,
        _navigationService = navigationService;

  final NoteReplyWebViewCookieService _cookieService;
  final NoteReplyWebViewNavigationService _navigationService;

  @override
  Future<bool> setAuthCookies() {
    return _cookieService.setAuthCookies();
  }

  @override
  String buildMessageUrl(String messageLink) {
    return _navigationService.buildMessageUrl(messageLink);
  }

  @override
  bool isSentMessagesListUrl(String url) {
    return _navigationService.isSentMessagesListUrl(url);
  }

  @override
  String buildFormScript({
    required String replyText,
    required String originalContent,
    required String recipient,
    required String subject,
  }) {
    return buildNoteReplyFormScript(
      replyText: replyText,
      originalContent: originalContent,
      recipient: recipient,
      subject: subject,
    );
  }
}
