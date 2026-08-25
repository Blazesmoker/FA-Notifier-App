abstract interface class SubmissionFolderColorRepository {
  Future<Map<String, int>> colorsFor(Iterable<String> folderNames);

  Future<void> setColor(String folderName, int colorValue);
}
