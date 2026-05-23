// lib/utils/fa_link_handler.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';
import 'package:FANotifier/features/journals/presentation/openjournal.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:FANotifier/features/profile/domain/profile_section.dart';
import 'package:FANotifier/shared/utils/fa_link_matcher.dart';

/// Centralized FA link handler.
Future<void> handleFALink(
  BuildContext context,
  String url, {
  String? htmlSource,
  String Function(String url, {String? htmlSource})? getFullUrl,
}) async {
  String fullUrlToMatch = url;
  if (url.contains('.....')) {
    if (getFullUrl != null) {
      final recovered = getFullUrl(url, htmlSource: htmlSource);
      fullUrlToMatch = recovered;
    }
  }
  final target = matchFALink(fullUrlToMatch);

  switch (target.type) {
    case FALinkTargetType.gallery:
      Navigator.push(
        context,
        UserProfileScreen.route(
          nickname: target.username!,
          initialSection: ProfileSection.Gallery,
        ),
      );
      return;
    case FALinkTargetType.galleryFolder:
      final tappedUsername = target.username!;
      final folderNumber = target.folderNumber!;
      final folderName = target.folderName!;
      final String folderUrl =
          'https://www.furaffinity.net/gallery/$tappedUsername/folder/$folderNumber/$folderName/';
      Navigator.push(
        context,
        UserProfileScreen.route(
          nickname: tappedUsername,
          initialSection: ProfileSection.Gallery,
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
          initialSection: ProfileSection.Journals,
        ),
      );
      return;
    case FALinkTargetType.journal:
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenJournal(uniqueNumber: target.journalId!),
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
        fullUrlToMatch,
        mode: LaunchMode.externalApplication,
      );
      return;
  }
}
