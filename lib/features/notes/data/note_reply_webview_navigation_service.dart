class NoteReplyWebViewNavigationService {
  const NoteReplyWebViewNavigationService();

  String buildMessageUrl(String messageLink) {
    return 'https://www.furaffinity.net$messageLink';
  }

  bool isSentMessagesListUrl(String url) {
    return url.contains('/msg/pms/') && !url.contains('/viewmessage/');
  }
}
