// lib/utils/fa_link_handler.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../home_screen.dart';
import '../main.dart';
import '../providers/NotificationNavigationProvider.dart';
import '../screens/notesscreen.dart';
import '../screens/submissions_screen.dart';
import '../screens/user_profile_screen.dart';
import '../screens/openpost.dart';
import '../screens/openjournal.dart';
import '../screens/notifications_screen.dart';

Future<void> handleFALink(BuildContext context, String url) async {
  final Uri uri       = Uri.parse(url);
  final List<String> segments = uri.pathSegments;
  final String? anchor        = uri.fragment.isEmpty ? null : uri.fragment;



  // 1) Gallery folder

  if (segments.length >= 5 &&
      segments[0] == 'gallery' &&
      segments[2] == 'folder') {
    final tappedUser = segments[1];
    final folderId   = segments[3];
    final folderName = segments[4];
    final folderUrl  =
        'https://www.furaffinity.net/gallery/$tappedUser/folder/$folderId/$folderName/';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          nickname: tappedUser,
          initialSection: ProfileSection.Gallery,
          initialFolderUrl: folderUrl,
          initialFolderName: folderName,
        ),
      ),
    );
    return;
  }


  // 2) User profile:

  if (segments.length >= 2 && segments[0] == 'user') {
    final tappedUser = segments[1];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(nickname: tappedUser),
      ),
    );
    return;
  }


  // 3) Journal list:

  if (segments.length >= 2 && segments[0] == 'journals') {
    final tappedUser = segments[1];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          nickname: tappedUser,
          initialSection: ProfileSection.Journals,
        ),
      ),
    );
    return;
  }


  // 4) Single journal:

  if (segments.length >= 2 && segments[0] == 'journal') {
    final journalId = segments[1];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OpenJournal(uniqueNumber: journalId),
      ),
    );
    return;
  }


  // 5) Submission screen:

  if (segments.length >= 2 && segments[0] == 'view') {
    final submissionId = segments[1];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OpenPost(
          uniqueNumber: submissionId,
          imageUrl: '',
        ),
      ),
    );
    return;
  }


  // 6) Submissions screen:

  if (segments.length >= 2 && segments[0] == 'msg' && segments[1] == 'submissions') {
    Navigator.of(context).popUntil((r) => r.isFirst);
    Provider.of<NotificationNavigationProvider>(context, listen: false)
        .setTargetIndex(2);
    return;
  }


  // 7) Notifications screen:

  if (segments.length >= 2 &&
      segments[0] == 'msg' &&
      segments[1] == 'others' &&
      (anchor == 'watches' || anchor == 'comments' || anchor == 'favorites')) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    Provider.of<NotificationNavigationProvider>(context, listen: false)
        .setTargetIndex(3);
    return;
  }

  // 8) Notes screen:

  if (segments.length >= 2 && segments[0] == 'msg' && segments[1] == 'pms') {
    Navigator.of(context).popUntil((r) => r.isFirst);
    Provider.of<NotificationNavigationProvider>(context, listen: false)
        .setTargetIndex(4);
    return;
  }


  // 7) Fallback: default screen

  Navigator.of(context).popUntil((r) => r.isFirst);
  Provider.of<NotificationNavigationProvider>(context, listen: false)
      .setTargetIndex(0);

}
