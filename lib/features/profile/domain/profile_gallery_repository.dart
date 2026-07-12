import 'package:FANotifier/features/profile/domain/profile_gallery_page_data.dart';
import 'package:FANotifier/features/profile/domain/profile_submission_data.dart';

abstract interface class ProfileGalleryRepository {
  String buildInitialGalleryUrl(String username, String selectedFolderUrl);

  String buildDefaultGalleryUrl(String username);

  String normalizeFolderUrl(String selectedFolderUrl);

  Future<ProfileGalleryPageData> fetchGalleryPage({
    required String url,
    String? selectedFolderUrl,
  });

  Future<ProfileSubmissionData> fetchSubmissionData(String postUrl);
}
