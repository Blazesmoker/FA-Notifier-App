enum SubmissionFavoriteLinksLoadStatus { missingAuth, httpFailure, success }

class SubmissionFavoriteLinksLoadResult {
  const SubmissionFavoriteLinksLoadResult({
    required this.status,
    this.statusCode,
    this.favoriteLink,
    this.unfavoriteLink,
  });

  final SubmissionFavoriteLinksLoadStatus status;
  final int? statusCode;
  final String? favoriteLink;
  final String? unfavoriteLink;

  bool get isFavorited => unfavoriteLink != null;
}
