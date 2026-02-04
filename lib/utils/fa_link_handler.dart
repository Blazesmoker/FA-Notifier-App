// lib/utils/fa_link_handler.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../screens/openpost.dart';
import '../screens/openjournal.dart';
import '../screens/user_profile_screen.dart';

/// Centralized FA link handler.
Future<void> handleFALink(
  BuildContext context,
  String url, {
  String? htmlSource,
  String Function(String url, {String? htmlSource})? getFullUrl,
}) async {
  // 1. Recover full/truncated URL if possible (for html rewritten links)
  String fullUrlToMatch = url;
  if (url.contains('.....')) {
    if (getFullUrl != null) {
      final recovered = getFullUrl(url, htmlSource: htmlSource);
      fullUrlToMatch = recovered;
    }
    // Fallback to htmlSource parsing if available (legacy screens)
    else if (htmlSource != null) {
      // This block can be specialized with custom recovery code if required
    }
  }
  final Uri uri = Uri.parse(fullUrlToMatch);
  final String urlToMatch = uri.toString();

  // Gallery folder with or without folder segments
  final RegExp galleryFolderRegex = RegExp(
      r'^https?://(?:www\.)?furaffinity\.net/gallery/([a-zA-Z0-9\-_.~]+)(?:/folder/(\d+)/([a-zA-Z0-9\-_.~]+))?/?$');
  final matchGallery = galleryFolderRegex.firstMatch(urlToMatch);
  if (matchGallery != null) {
    final String tappedUsername = matchGallery.group(1)!;
    final String? folderNumber = matchGallery.group(2);
    final String? folderName = matchGallery.group(3);
    if (folderNumber != null && folderName != null) {
      // specific folder
      final String folderUrl =
        'https://www.furaffinity.net/gallery/$tappedUsername/folder/$folderNumber/$folderName/';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            nickname: tappedUsername,
            initialSection: ProfileSection.Gallery,
            initialFolderUrl: folderUrl,
            initialFolderName: folderName,
          ),
        ),
      );
    } else {
      // just the gallery
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            nickname: tappedUsername,
            initialSection: ProfileSection.Gallery,
          ),
        ),
      );
    }
    return;
  }

  // User profile
  final RegExp userRegex = RegExp(r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([a-zA-Z0-9\-_.~]+)/?$');
  final matchUser = userRegex.firstMatch(urlToMatch);
  if (matchUser != null) {
    final tappedUsername = matchUser.group(1)!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(nickname: tappedUsername),
      ),
    );
    return;
  }

  // Journals: /journals/username or /journal/id
  final RegExp journalRegex = RegExp(r'^(?:https?://(?:www\.)?furaffinity\.net)?/(?:journals/([a-zA-Z0-9\-_.~]+)|journal/(\d+))(?:/.*)?(?:#.*)?$');
  final matchJournal = journalRegex.firstMatch(urlToMatch);
  if (matchJournal != null) {
    final String? username = matchJournal.group(1);
    final String? journalId = matchJournal.group(2);
    if (username != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            nickname: username,
            initialSection: ProfileSection.Journals,
          ),
        ),
      );
    } else if (journalId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenJournal(uniqueNumber: journalId),
        ),
      );
    }
    return;
  }

  // Submission/view
  final RegExp viewRegex = RegExp(r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$');
  final matchView = viewRegex.firstMatch(urlToMatch);
  if (matchView != null) {
    final submissionId = matchView.group(1)!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OpenPost(
          uniqueNumber: submissionId,
          imageUrl: '',
        ),
      ),
    );
    return;
  }

  // fallback: open externally
  await launchUrlString(fullUrlToMatch, mode: LaunchMode.externalApplication);
}
