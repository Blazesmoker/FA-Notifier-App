import 'package:intl/intl.dart';

class OpenPostParseResult {
  OpenPostParseResult({
    required this.currentUsername,
    required this.username,
    required this.linkUsername,
    required this.profileImageUrl,
    required this.submissionTitle,
    required this.fullViewImageUrl,
    required this.submissionDescription,
    required this.publicationTimeRaw,
    required this.rating,
    required this.favoritesCount,
    required this.viewCount,
    required this.commentsCount,
    required this.favLink,
    required this.unfavLink,
    required this.isFavorited,
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

  final String? currentUsername;
  final String? username;
  final String? linkUsername;
  final String? profileImageUrl;
  final String? submissionTitle;
  final String? fullViewImageUrl;
  final String? submissionDescription;
  final String? publicationTimeRaw;
  final String? rating;
  final int favoritesCount;
  final int viewCount;
  final int commentsCount;
  final String? favLink;
  final String? unfavLink;
  final bool isFavorited;
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

class FaPostTag {
  const FaPostTag({
    required this.name,
    required this.isBlocked,
    required this.isMeta,
    required this.isSearchable,
  });

  final String name;
  final bool isBlocked;
  final bool isMeta;
  final bool isSearchable;
}

class OpenPostUserPageActions {
  const OpenPostUserPageActions({
    required this.isClassic,
    this.watchLink,
    this.unwatchLink,
    this.blockLink,
    this.unblockLink,
    this.blockKey,
    this.unblockKey,
  });

  final bool isClassic;
  final String? watchLink;
  final String? unwatchLink;
  final String? blockLink;
  final String? unblockLink;
  final String? blockKey;
  final String? unblockKey;

  bool get isWatching => unwatchLink != null;
  bool get isBlocked => unblockLink != null;
}

DateTime? parseSubmissionPublicationTime(
  String rawTime, {
  required bool applyDstCorrection,
}) {
  final trimmed = rawTime.trim();

  final formats = [
    DateFormat('MMMM d, yyyy hh:mm:ss a'),
    DateFormat('MMM d, yyyy hh:mm:ss a'),
    DateFormat('MMM d, yyyy HH:mm:ss'),
    DateFormat('MMM d, yyyy hh:mm a'),
    DateFormat('MMM d, yyyy HH:mm'),
    DateFormat('yyyy-MM-dd HH:mm:ss'),
  ];

  for (final format in formats) {
    try {
      var parsed = format.parse(trimmed);
      if (applyDstCorrection) {
        parsed = parsed.subtract(const Duration(hours: 1));
      }
      return parsed.toUtc();
    } catch (_) {}
  }

  return null;
}
