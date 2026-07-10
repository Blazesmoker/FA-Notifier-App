import 'package:FANotifier/features/submissions/domain/openpost_models.dart';

class OpenPostSubmissionStats {
  const OpenPostSubmissionStats({
    required this.viewCount,
    required this.commentsCount,
    required this.rating,
    required this.favoritesCount,
    required this.favLink,
    required this.unfavLink,
  });

  final int viewCount;
  final int commentsCount;
  final String? rating;
  final int favoritesCount;
  final String? favLink;
  final String? unfavLink;
}

class OpenPostSubmissionMetadata {
  const OpenPostSubmissionMetadata({
    required this.category,
    required this.type,
    required this.species,
    required this.gender,
    required this.size,
    required this.fileSize,
    required this.keywords,
    required this.keywordTags,
    required this.metaKeywordTags,
    required this.tagBlocklistNonce,
    required this.imageWidth,
    required this.imageHeight,
  });

  final String? category;
  final String? type;
  final String? species;
  final String? gender;
  final String? size;
  final String? fileSize;
  final List<String> keywords;
  final List<FaPostTag> keywordTags;
  final List<FaPostTag> metaKeywordTags;
  final String? tagBlocklistNonce;
  final double? imageWidth;
  final double? imageHeight;
}
