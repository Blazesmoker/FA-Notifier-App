import 'package:fanotifier/features/profile/domain/fa_folder.dart';

FaFolder resolveProfileFolderSelection({
  required List<FaFolder> folders,
  required String selectedName,
  required String selectedUrl,
}) {
  if (selectedUrl.isNotEmpty) {
    return folders.firstWhere(
      (folder) => areFaFolderUrlsEquivalent(folder.url, selectedUrl),
      orElse: () => FaFolder(name: selectedName, url: selectedUrl),
    );
  }
  if (folders.isNotEmpty) {
    return folders.firstWhere(
      (folder) => folder.name == 'Main Gallery',
      orElse: () => folders.first,
    );
  }
  return FaFolder(name: selectedName, url: selectedUrl);
}
