import 'package:fanotifier/features/submissions/data/submission_description_service.dart';
import 'package:fanotifier/features/submissions/data/submission_description_webview_html_builder.dart';
import 'package:fanotifier/features/submissions/domain/submission_description_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_description_webview_content.dart';

class SubmissionDescriptionRepositoryImpl
    implements SubmissionDescriptionRepository {
  SubmissionDescriptionRepositoryImpl({SubmissionDescriptionService? service})
      : _service = service ?? SubmissionDescriptionService();

  final SubmissionDescriptionService _service;

  @override
  Future<SubmissionDescriptionWebViewContent> processInitialHtml(
    String html,
  ) async {
    final extractedHtml = await _service.extractInitialHtml(html);
    final htmlWithInlinedIcons = await _service.inlineIcons(extractedHtml);
    return _service.buildWebViewContent(htmlWithInlinedIcons);
  }

  @override
  Future<SubmissionDescriptionWebViewContent> fetchContent(
    String submissionId,
  ) async {
    final extractedHtml =
        await _service.fetchDescriptionHtml(submissionId);
    final htmlWithInlinedIcons = await _service.inlineIcons(extractedHtml);
    return _service.buildWebViewContent(htmlWithInlinedIcons);
  }

  @override
  String findFullLink(String htmlSource, String truncatedUrl) {
    return _service.findFullLink(htmlSource, truncatedUrl);
  }

  @override
  String plainText(String html) {
    return _service.plainText(html);
  }

  @override
  String buildWebViewHtml({
    required String submissionDescriptionHtml,
    required String faThemeCss,
    required bool enableTextSelection,
  }) {
    return buildSubmissionDescriptionWebViewHtml(
      submissionDescriptionHtml: submissionDescriptionHtml,
      faThemeCss: faThemeCss,
      enableTextSelection: enableTextSelection,
    );
  }
}
