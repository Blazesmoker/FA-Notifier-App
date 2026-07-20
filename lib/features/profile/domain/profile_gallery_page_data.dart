import 'package:fanotifier/features/profile/domain/fa_folder.dart';

class ProfileGalleryPageData {
  const ProfileGalleryPageData({
    required this.posts,
    required this.nextPageUrl,
    required this.folders,
  });

  final List<Map<String, dynamic>> posts;
  final String? nextPageUrl;
  final List<FaFolder> folders;
}
