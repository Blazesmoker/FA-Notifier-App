import 'dart:io';

import 'package:FANotifier/features/submissions/data/submission_detail_parser.dart';
import 'package:FANotifier/features/submissions/data/submissions_listing_parser.dart';
import 'package:FANotifier/features/submissions/domain/submission_fetch_models.dart';
import 'package:FANotifier/features/submissions/domain/submissions_listing_parse_result.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class SubmissionsService {
  SubmissionsService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<bool> hasAuthCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a') ?? '';
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b') ?? '';
    return cookieA.isNotEmpty && cookieB.isNotEmpty;
  }

  Future<SubmissionsListingParseResult> fetchListing({
    required String? nextPageUrl,
    required String? baseSubmissionsUrl,
    required bool sfwEnabled,
  }) async {
    final cookieHeader = await buildAuthCookieHeader(
      includeSfw: true,
      sfwEnabled: sfwEnabled,
    );
    final url = nextPageUrl ??
        baseSubmissionsUrl ??
        'https://www.furaffinity.net/msg/submissions/';
    debugPrint('[Submissions] GET $url');

    final resp = await FAHttp.get(
      Uri.parse(url),
      headers: {
        HttpHeaders.cookieHeader: cookieHeader,
        'User-Agent': FAHttp.userAgent,
      },
    );

    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode}');
    }

    return parseSubmissionsListing(resp.body);
  }

  Future<bool> nukeSubmissions({
    required String? baseSubmissionsUrl,
  }) async {
    final cookieHeader = await buildAuthCookieHeader();
    if (cookieHeader.isEmpty) return false;

    final url =
        baseSubmissionsUrl ?? 'https://www.furaffinity.net/msg/submissions/new/';
    final resp = await http.post(
      Uri.parse(url),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
      },
      body: {'messagecenter-action': 'nuke_notifications'},
    );
    return resp.statusCode == 302;
  }

  Future<bool> deleteSubmissions({
    required String? baseSubmissionsUrl,
    required Iterable<String> submissionIds,
  }) async {
    final cookieHeader = await buildAuthCookieHeader();
    if (cookieHeader.isEmpty) return false;

    final body = <String, String>{'messagecenter-action': 'remove_checked'};
    int idx = 0;
    for (final id in submissionIds) {
      body['submissions[$idx]'] = id;
      idx++;
    }
    final deleteUrl =
        baseSubmissionsUrl ?? 'https://www.furaffinity.net/msg/submissions/new/';
    final resp = await http.post(
      Uri.parse(deleteUrl),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );

    return resp.statusCode == 302;
  }

  Future<SubmissionData> fetchSubmissionData(String postUrl) async {
    final absoluteUrl = postUrl.startsWith('http')
        ? postUrl
        : 'https://www.furaffinity.net$postUrl';
    debugPrint('[Submissions] HQ fetch: $absoluteUrl');

    final cookieHeader = await buildAuthCookieHeader();
    final resp = await FAHttp.get(
      Uri.parse(absoluteUrl),
      headers: {
        HttpHeaders.cookieHeader: cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );

    if (resp.statusCode != 200) {
      throw Exception('Submission detail fetch failed: ${resp.statusCode}');
    }

    return parseSubmissionDetailData(resp.bodyBytes);
  }

  Future<String> buildAuthCookieHeader({
    bool includeSfw = false,
    bool sfwEnabled = false,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a') ?? '';
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b') ?? '';
    if (cookieA.isEmpty || cookieB.isEmpty) {
      return '';
    }
    var cookieHeader = 'a=$cookieA; b=$cookieB';
    if (includeSfw && sfwEnabled) cookieHeader += '; sfw=1';
    return FaCookieHelper.appendCfClearanceToCookieHeader(cookieHeader);
  }
}
