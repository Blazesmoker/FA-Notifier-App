import 'dart:io';

import 'package:FANotifier/features/browse/data/browse_image_parser.dart';
import 'package:FANotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';
import 'package:FANotifier/shared/fa/fa_system_message_parser.dart';
import 'package:FANotifier/shared/utils/content_rating_filters.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BrowseImageService {
  BrowseImageService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<List<Map<String, dynamic>>> fetchImages({
    required int pageNumber,
    required Map<String, String> selectedFilters,
    required bool sfwEnabled,
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

    var resp = await FAHttp.post(uri, headers: headers, body: body);

    if (resp.isRedirect || (resp.statusCode >= 300 && resp.statusCode < 400)) {
      final loc = resp.headers['location'];
      if (loc == null || loc.isEmpty) {
        throw Exception('Redirect without Location header');
      }
      final redirectUri = uri.resolve(loc);
      currentUri = redirectUri;
      resp = await FAHttp.get(
        redirectUri,
        headers: {
          HttpHeaders.cookieHeader:
              await FaCookieHelper.appendCfClearanceToCookieHeader(
            cookieHeader,
          ),
          'User-Agent': FAHttp.userAgent,
          'Referer': uri.toString(),
        },
      );
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
    );
    if (isChallenge) {
      throw CloudflareChallengeException(initialUrl: currentUri.toString());
    }

    if (resp.statusCode == 200) {
      final faMessage = parseFaSystemMessage(resp.body);
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
      return parseBrowseImageHtml(resp.body);
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
