class SubmissionFavoriteLinks {
  final String favUrl;
  final String unfavUrl;

  const SubmissionFavoriteLinks({
    required this.favUrl,
    required this.unfavUrl,
  });

  bool get hasFavUrl => favUrl.isNotEmpty;
  bool get hasUnfavUrl => unfavUrl.isNotEmpty;
  bool get hasAnyUrl => hasFavUrl || hasUnfavUrl;
  bool get isFavorited => hasUnfavUrl && !hasFavUrl;
}
