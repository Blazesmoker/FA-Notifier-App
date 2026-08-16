import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fanotifier/features/journals/presentation/openjournal.dart';
import 'package:fanotifier/features/profile/domain/profile_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:fanotifier/features/submissions/presentation/openpost.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/utils/fa_link_matcher.dart';

class AppFaLinkNavigator extends FaLinkNavigator {
  const AppFaLinkNavigator();

  @override
  Future<void> open(
    BuildContext context,
    FALinkTarget target,
    String resolvedUrl,
  ) async {
    switch (target.type) {
      case FALinkTargetType.gallery:
        Navigator.push(
          context,
          UserProfileScreen.route(
            nickname: target.username!,
            initialSection: ProfileSection.gallery,
          ),
        );
        return;
      case FALinkTargetType.galleryFolder:
        final username = target.username!;
        final folderNumber = target.folderNumber!;
        final folderName = target.folderName!;
        final folderUrl = buildFAGalleryFolderUrl(
          username: username,
          folderNumber: folderNumber,
          folderName: folderName,
        );
        Navigator.push(
          context,
          UserProfileScreen.route(
            nickname: username,
            initialSection: ProfileSection.gallery,
            initialFolderUrl: folderUrl,
            initialFolderName: folderName,
          ),
        );
        return;
      case FALinkTargetType.user:
        Navigator.push(
          context,
          UserProfileScreen.route(nickname: target.username!),
        );
        return;
      case FALinkTargetType.journalUser:
        Navigator.push(
          context,
          UserProfileScreen.route(
            nickname: target.username!,
            initialSection: ProfileSection.journals,
          ),
        );
        return;
      case FALinkTargetType.journal:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OpenJournal(
              uniqueNumber: target.journalId!,
            ),
          ),
        );
        return;
      case FALinkTargetType.submission:
        Navigator.push(
          context,
          OpenPost.route(
            uniqueNumber: target.submissionId!,
            imageUrl: '',
          ),
        );
        return;
      case FALinkTargetType.external:
        await launchUrlString(
          resolvedUrl,
          mode: LaunchMode.externalApplication,
        );
        return;
    }
  }
}
