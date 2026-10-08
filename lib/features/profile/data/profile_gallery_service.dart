import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/profile/data/profile_posts_parser.dart';
import 'package:fanotifier/features/profile/data/profile_submission_parser.dart';
import 'package:fanotifier/features/profile/domain/profile_gallery_page_data.dart';
import 'package:fanotifier/features/profile/domain/profile_gallery_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_submission_data.dart';
import 'package:fanotifier/core/network/fa_http.dart';

String buildDefaultProfileGalleryUrl(String username) {
  return 'https://www.furaffinity.net/gallery/$username/';
}

class ProfileGalleryService implements ProfileGalleryRepository {
  ProfileGalleryService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;
  final SfwModePreference _sfwModePreference = SfwModePreference();

  @override
  String buildInitialGalleryUrl(String username, String selectedFolderUrl) {
    if (selectedFolderUrl.isNotEmpty) {
      return selectedFolderUrl;
    }
    return buildDefaultGalleryUrl(username);
  }

  @override
  String buildDefaultGalleryUrl(String username) {
    return buildDefaultProfileGalleryUrl(username);
  }

  @override
  String normalizeFolderUrl(String selectedFolderUrl) {
    return selectedFolderUrl.replaceAll(RegExp(r'/$'), '');
  }

  @override
  Future<ProfileGalleryPageData> fetchGalleryPage({
    required String url,
    String? selectedFolderUrl,
    bool Function()? isCancelled,
  }) async {
    debugPrint("Fetching URL: $url");
    final cookieHeader = await _buildCookieHeader();
    final response = await FAHttp.get(
      Uri.parse(url),
      isCancelled: isCancelled,
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load images: ${response.statusCode}');
    }

    if (isCancelled?.call() ?? false) {
      throw StateError('FA request cancelled');
    }
    final parseRes = await parseProfileGalleryPage(
      response.bodyBytes,
      url,
      selectedFolderUrl: selectedFolderUrl,
    );
    if (isCancelled?.call() ?? false) {
      throw StateError('FA request cancelled');
    }

    for (final post in parseRes.posts) {
      post['hqUrl'] = null;
      post['isFav'] = false;
      post['initialIsFav'] = null;
      post['favUrl'] = '';
      post['unfavUrl'] = '';
      post['detailFetchQueued'] = false;
      post['detailFetchInProgress'] = false;
      post['detailFetched'] = false;
      post['detailFetchVisibilityGeneration'] = 0;
    }

    return ProfileGalleryPageData(
      posts: parseRes.posts,
      nextPageUrl: parseRes.nextPageUrl,
      folders: parseRes.folders,
    );
  }

  @override
  Future<ProfileSubmissionData> fetchSubmissionData(
    String postUrl, {
    bool Function()? isCancelled,
  }) async {
    final absolute =
        Uri.parse('https://www.furaffinity.net').resolve(postUrl).toString();

    final cookieHeader = await _buildCookieHeader();
    final resp = await FAHttp.get(
      Uri.parse(absolute),
      isCancelled: isCancelled,
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Submission page fetch failed: ${resp.statusCode}');
    }

    if (isCancelled?.call() ?? false) {
      throw StateError('FA request cancelled');
    }
    final parsed = await parseProfileSubmissionPage(resp.bodyBytes);
    if (isCancelled?.call() ?? false) {
      throw StateError('FA request cancelled');
    }
    return parsed;
  }

  Future<String> _buildCookieHeader() async {
    final sfwValue = await _getSfwCookieValue();
    final keys = ['a', 'b', 'cc', 'cf_clearance', 'folder', 'nodesc', 'sz'];
    final parts = <String>[];
    for (final key in keys) {
      final val = await _secureStorage.read(key: 'fa_cookie_$key');
      if (val != null && val.isNotEmpty) {
        parts.add('$key=$val');
      }
    }
    parts.add('sfw=$sfwValue');
    return parts.join('; ');
  }

  Future<String> _getSfwCookieValue() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    return sfwEnabled ? '1' : '0';
  }
}
