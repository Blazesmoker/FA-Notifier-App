import 'package:FANotifier/features/submissions/domain/openpost_models.dart';

class OpenPostTagBlockState {
  const OpenPostTagBlockState({
    required this.keywordTags,
    required this.metaKeywordTags,
    required this.updated,
  });

  final List<FaPostTag> keywordTags;
  final List<FaPostTag> metaKeywordTags;
  final bool updated;
}

OpenPostTagBlockState updateOpenPostTagBlockState({
  required List<FaPostTag> keywordTags,
  required List<FaPostTag> metaKeywordTags,
  required String tagName,
  required bool isBlocked,
}) {
  var updated = false;

  FaPostTag updateTag(FaPostTag tag) {
    return FaPostTag(
      name: tag.name,
      isBlocked: isBlocked,
      isMeta: tag.isMeta,
      isSearchable: tag.isSearchable,
    );
  }

  final updatedKeywords = keywordTags.map((tag) {
    if (tag.name != tagName) return tag;
    updated = true;
    return updateTag(tag);
  }).toList(growable: false);

  final updatedMeta = metaKeywordTags.map((tag) {
    if (tag.name != tagName) return tag;
    updated = true;
    return updateTag(tag);
  }).toList(growable: false);

  return OpenPostTagBlockState(
    keywordTags: updatedKeywords,
    metaKeywordTags: updatedMeta,
    updated: updated,
  );
}
