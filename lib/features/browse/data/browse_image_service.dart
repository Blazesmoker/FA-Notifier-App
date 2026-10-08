import 'dart:io';

import 'package:fanotifier/features/browse/domain/browse_page_data.dart';
import 'package:fanotifier/features/browse/data/browse_image_parser.dart';
import 'package:fanotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';
import 'package:fanotifier/shared/utils/content_rating_filters.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BrowseImageService {
  BrowseImageService({
    FlutterSecureStorage? secureStorage,
    this._onDocumentCookies,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;
  final Future<void> Function({required Uri documentUri, required String? setCookieHeader})?
      _onDocumentCookies;

  Future<BrowsePageData> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
    bool Function()? isCancelled,
  }) async {
    final cookieHeader = await buildCookieHeader(
      selectedFilters: selectedFilters,
      sfwEnabled: sfwEnabled,
    );
    final uri = Uri.parse('https://www.furaffinity.net/browse/$pageNumber');
    Uri currentUri = uri;

    final headers = {
      HttpHeaders.cookieHeader:
          await FaCookieHelper.appendCfClearanceToCookieHeader(cookieHeader),
      'User-Agent': FAHttp.userAgent,
      'Referer': 'https://www.furaffinity.net/browse/',
      'Content-Type': 'application/x-www-form-urlencoded',
    };

    final body = {
      'cat': _getFilterValue(selectedFilters, 'Category'),
      'atype': _getFilterValue(selectedFilters, 'Type'),
      'species': _getFilterValue(selectedFilters, 'Species'),
      'gender': _getFilterValue(selectedFilters, 'Gender'),
      'rating_general': _getFilterValue(selectedFilters, 'rating-general'),
      'rating_mature': _getFilterValue(selectedFilters, 'rating-mature'),
      'rating_adult': _getFilterValue(selectedFilters, 'rating-adult'),
      'perpage': '72',
      'btn': 'Next',
    };

    final loaded = await FAHttp.postWithResolvedUri(
      uri, headers: headers, body: body,
      isCancelled: isCancelled, coordinatorLabel: 'Browse page',
      followRedirects: false,
    );
    currentUri = loaded.resolvedUri;
    var resp = loaded.response;
    var method = 'POST';
    final seen = {'$method $currentUri'};
    for (var hop = 0; ; hop++) {
      if (isCancelled?.call() ?? false) throw StateError('Browse request cancelled');
      await _onDocumentCookies?.call(
        documentUri: currentUri, setCookieHeader: resp.headers['set-cookie'],
      );
      if (isCancelled?.call() ?? false) throw StateError('Browse request cancelled');
      if (![301, 302, 303, 307, 308].contains(resp.statusCode)) break;
      if (hop >= 5) throw Exception('Too many Browse redirects.');
      final loc = resp.headers['location'];
      if (loc == null || loc.isEmpty) {
        throw Exception('Redirect without Location header');
      }
      final redirectUri = currentUri.resolve(loc);
      method = resp.statusCode == 307 || resp.statusCode == 308 ? method : 'GET';
      if (redirectUri.scheme != 'https' || redirectUri.userInfo.isNotEmpty ||
          (redirectUri.host != 'www.furaffinity.net' && redirectUri.host != 'furaffinity.net') ||
          !seen.add('$method $redirectUri')) {
        throw Exception('Invalid Browse redirect.');
      }
      final redirectHeaders = {
        HttpHeaders.cookieHeader: await FaCookieHelper.appendCfClearanceToCookieHeader(
          await buildCookieHeader(selectedFilters: selectedFilters, sfwEnabled: sfwEnabled),
        ),
        'User-Agent': FAHttp.userAgent,
        'Referer': currentUri.toString(),
      };
      final redirected = method == 'POST'
          ? await FAHttp.postWithResolvedUri(
              redirectUri, body: body, headers: redirectHeaders,
              isCancelled: isCancelled, coordinatorLabel: 'Browse page redirect',
              followRedirects: false,
            )
          : await FAHttp.getWithResolvedUri(
              redirectUri, headers: redirectHeaders,
              isCancelled: isCancelled, coordinatorLabel: 'Browse page redirect',
              followRedirects: false,
            );
      resp = redirected.response;
      currentUri = redirected.resolvedUri;
    }

    final refreshedCf = FaCookieHelper.extractCfClearanceFromSetCookieHeader(
      resp.headers['set-cookie'],
    );
    if (refreshedCf != null && refreshedCf.isNotEmpty) {
      await FaCookieHelper.writeCfClearance(refreshedCf);
    }

    final isChallenge = FaCookieHelper.isCloudflareChallengePage(
      body: resp.body,
      statusCode: resp.statusCode,
      headers: resp.headers,
    );
    if (isChallenge) {
      throw CloudflareChallengeException(initialUrl: currentUri.toString());
    }

    if (resp.statusCode == 200) {
      final parsed = await parseBrowsePageHtml(
        html: resp.body,
        documentUri: currentUri,
        sfwEnabled: ContentRatingFilters.effectiveSfwCookieValue(
              globalSfwEnabled: sfwEnabled,
              filters: selectedFilters,
            ) == '1',
      );
      if (isCancelled?.call() ?? false) throw StateError('Browse request cancelled');
      final faMessage = parsed.systemMessage;
      if (faMessage != null) {
        if (faMessage.isMaintenanceOrUnavailable) {
          FaRequestCoordinator.instance.recordMaintenanceOrUnavailable(
            message: faMessage.message,
            retryAfter: faMessage.retryAfter,
          );
          throw FaMaintenanceUnavailableException(faMessage.message);
        }
        throw Exception(faMessage.message);
      }
      return parsed.page;
    }

    throw Exception('FAImageGrid: HTTP ${resp.statusCode} fetching images.');
  }

  Future<String> buildCookieHeader({
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
  }) async {
    final cookieNames = [
      'a',
      'b',
      'cc',
      'cf_clearance',
      'folder',
      'nodesc',
      'sz'
    ];
    final cookies = <String>[];
    for (var name in cookieNames) {
      final storageKey = 'fa_cookie_$name';
      final value = await _secureStorage.read(key: storageKey);
      if (value != null && value.isNotEmpty) {
        cookies.add('$name=$value');
      }
    }
    cookies.add(
      'sfw=${ContentRatingFilters.effectiveSfwCookieValue(globalSfwEnabled: sfwEnabled, filters: selectedFilters)}',
    );
    return cookies.join('; ');
  }

  String _getFilterValue(
    Map<String, String> selectedFilters,
    String filterName,
  ) {
    return selectedFilters[filterName] ?? '1';
  }
}
