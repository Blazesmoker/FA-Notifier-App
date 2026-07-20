import 'package:fanotifier/features/profile/domain/user_description_webview_content.dart';

abstract interface class UserDescriptionRepository {
  Future<String> extractInitialHtml(String html);

  Future<String> inlineIcons(String html);

  Future<UserDescriptionWebViewContent> buildWebViewContent(String html);

  String findFullLink(String htmlSource, String truncatedUrl);

  String plainText(String html);

  Future<String> fetchCleanHtml(String sanitizedUsername);

  String buildWebViewHtml({
    required String userDescriptionHtml,
    required String faThemeCss,
    required bool enableTextSelection,
  });
}
