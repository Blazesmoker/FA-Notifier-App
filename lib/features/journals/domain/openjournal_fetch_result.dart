class OpenJournalFetchResult {
  OpenJournalFetchResult({
    required this.profileImageUrl,
    required this.displayName,
    required this.authorSlug,
    required this.symbol,
    required this.userTitle,
    required this.isJournalClassic,
    required this.ownerEditLink,
    required this.favoriteLink,
    required this.unfavoriteLink,
    required this.isFavorited,
    required this.watchLink,
    required this.unwatchLink,
    required this.isWatching,
    required this.blockLink,
    required this.unblockLink,
    required this.isBlocked,
    required this.title,
    required this.dateTime,
    required this.dateTimeRaw,
    required this.submissionDescription,
    required this.commentsCount,
    required this.fullViewImageUrl,
    required this.fileLink,
    required this.category,
    required this.type,
    required this.species,
    required this.gender,
    required this.keywords,
    required this.deleteLink,
    required this.commentBodies,
  });

  final String? profileImageUrl;
  final String? displayName;
  final String? authorSlug;
  final String? symbol;
  final String? userTitle;
  final bool isJournalClassic;
  final String? ownerEditLink;
  final String? favoriteLink;
  final String? unfavoriteLink;
  final bool isFavorited;
  final String? watchLink;
  final String? unwatchLink;
  final bool isWatching;
  final String? blockLink;
  final String? unblockLink;
  final bool isBlocked;
  final String? title;
  final DateTime? dateTime;
  final String? dateTimeRaw;
  final String? submissionDescription;
  final int commentsCount;
  final String? fullViewImageUrl;
  final String? fileLink;
  final String? category;
  final String? type;
  final String? species;
  final String? gender;
  final List<String> keywords;
  final String? deleteLink;
  final List<Map<String, dynamic>> commentBodies;
}
