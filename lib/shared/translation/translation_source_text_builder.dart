import 'package:fanotifier/shared/translation/translation_service.dart';

class TranslationSourceTextBuilder {
  const TranslationSourceTextBuilder(this._translationService);

  final TranslationService _translationService;

  String content({
    required String? title,
    required String? descriptionHtml,
  }) {
    final description = descriptionHtml == null
        ? ''
        : _translationService.plainTextFromHtml(descriptionHtml);
    return '${title ?? ''}\n$description'.trim();
  }

  bool isCommentAvailable(Map<String, dynamic> comment) {
    return comment['deleted'] != true;
  }

  String comment(Map<String, dynamic> comment) {
    final commentHtml = comment['commentHtml'] as String?;
    if (commentHtml != null && commentHtml.trim().isNotEmpty) {
      return _translationService.plainTextFromHtml(commentHtml);
    }
    return comment['text']?.toString() ?? '';
  }
}
