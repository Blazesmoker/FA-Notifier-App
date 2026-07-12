abstract interface class ProfileGalleryFavoriteRepository {
  Future<bool> hasAuthCookies();

  void toggleFavorite({
    required String uniqueNumber,
    required bool isFav,
    required String? favUrl,
    required String? unfavUrl,
    void Function(String uniqueNumber, bool finalState)? onPostComplete,
  });

  void cancelAll();
}
