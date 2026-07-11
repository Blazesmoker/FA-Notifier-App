enum OpenPostFavoriteLinksLoadStatus { missingAuth, httpFailure, success }

class OpenPostFavoriteLinksLoadResult {
  const OpenPostFavoriteLinksLoadResult({
    required this.status,
    this.statusCode,
    this.favoriteLink,
    this.unfavoriteLink,
  });

  final OpenPostFavoriteLinksLoadStatus status;
  final int? statusCode;
  final String? favoriteLink;
  final String? unfavoriteLink;

  bool get isFavorited => unfavoriteLink != null;
}
