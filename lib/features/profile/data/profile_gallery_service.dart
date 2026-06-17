import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/profile/data/profile_posts_parser.dart';
import 'package:FANotifier/features/profile/domain/fa_folder.dart';
import 'package:FANotifier/features/profile/domain/profile_submission_data.dart';
import 'package:FANotifier/features/submissions/data/submission_favorite_links_parser.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

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

String buildDefaultProfileGalleryUrl(String username) {
  return 'https://www.furaffinity.net/gallery/$username/';
}

class ProfileGalleryService {
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

  String buildInitialGalleryUrl(String username, String selectedFolderUrl) {
    if (selectedFolderUrl.isNotEmpty) {
      return selectedFolderUrl;
    }
    return buildDefaultGalleryUrl(username);
  }

  String buildDefaultGalleryUrl(String username) {
    return buildDefaultProfileGalleryUrl(username);
  }

  String normalizeFolderUrl(String selectedFolderUrl) {
    return selectedFolderUrl.replaceAll(RegExp(r'/$'), '');
  }

  Future<ProfileGalleryPageData> fetchGalleryPage({
    required String url,
    String? selectedFolderUrl,
  }) async {
    debugPrint("Fetching URL: $url");
    final cookieHeader = await _buildCookieHeader();
    final response = await FAHttp.get(
      Uri.parse(url),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load images: ${response.statusCode}');
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    final parseRes = parseProfileGalleryHtml(
      decodedBody,
      url,
      selectedFolderUrl: selectedFolderUrl,
    );

    for (final post in parseRes.posts) {
      post['hqUrl'] = null;
      post['isFav'] = false;
      post['initialIsFav'] = null;
      post['favUrl'] = '';
      post['unfavUrl'] = '';
      post['detailFetchQueued'] = false;
    }

    return ProfileGalleryPageData(
      posts: parseRes.posts,
      nextPageUrl: parseRes.nextPageUrl,
      folders: parseRes.folders,
    );
  }

  Future<ProfileSubmissionData> fetchSubmissionData(String postUrl) async {
    final absolute =
        Uri.parse('https://www.furaffinity.net').resolve(postUrl).toString();

    final cookieHeader = await _buildCookieHeader();
    final resp = await FAHttp.get(
      Uri.parse(absolute),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Submission page fetch failed: ${resp.statusCode}');
    }

    final doc = html_parser.parse(utf8.decode(resp.bodyBytes));
    String hqUrl = '';
    final subArea = doc.querySelector('div.submission-area.submission-image');
    if (subArea != null) {
      final img = subArea.querySelector('img#submissionImg');
      if (img != null) {
        final fullview = img.attributes['data-fullview-src'];
        if (fullview != null && fullview.isNotEmpty) {
          hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
        } else {
          final src = img.attributes['src'];
          if (src != null && src.isNotEmpty) {
            hqUrl = src.startsWith('//') ? 'https:$src' : src;
          }
        }
      }
    }

    if (hqUrl.isEmpty) {
      final img = doc.querySelector('img#submissionImg');
      if (img != null) {
        final fullview = img.attributes['data-fullview-src'];
        if (fullview != null && fullview.isNotEmpty) {
          hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
        } else {
          final src = img.attributes['src'];
          if (src != null && src.isNotEmpty) {
            hqUrl = src.startsWith('//') ? 'https:$src' : src;
          }
        }
      }
    }

    final favoriteLinks = parseSubmissionFavoriteLinksFromDocument(
      doc,
      includeClassicFallback: true,
    );

    return ProfileSubmissionData(
      hqUrl: hqUrl,
      isFav: favoriteLinks.isFavorited,
      favUrl: favoriteLinks.favUrl,
      unfavUrl: favoriteLinks.unfavUrl,
    );
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
