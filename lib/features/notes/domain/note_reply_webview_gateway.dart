abstract interface class NoteReplyWebViewGateway {
  Future<bool> setAuthCookies();

  String buildMessageUrl(String messageLink);

  bool isSentMessagesListUrl(String url);

  String buildFormScript({
    required String replyText,
    required String originalContent,
    required String recipient,
    required String subject,
  });
}
