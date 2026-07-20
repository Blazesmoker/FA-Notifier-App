import 'package:fanotifier/features/submissions/domain/submission_description_webview_content.dart';

abstract interface class SubmissionDescriptionRepository {
  Future<SubmissionDescriptionWebViewContent> processInitialHtml(String html);

  Future<SubmissionDescriptionWebViewContent> fetchContent(
    String submissionId,
  );

  String findFullLink(String htmlSource, String truncatedUrl);

  String plainText(String html);

  String buildWebViewHtml({
    required String submissionDescriptionHtml,
    required String faThemeCss,
    required bool enableTextSelection,
  });
}
