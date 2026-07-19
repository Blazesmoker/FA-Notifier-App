abstract interface class NoteGoogleImageResolver {
  Future<String?> resolveHighQualityImageUrl({
    required Uri pageUri,
    required String selectedId,
  });
}
