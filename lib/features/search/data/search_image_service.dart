import 'dart:io';

import 'package:fanotifier/features/search/data/search_image_parser.dart';
import 'package:fanotifier/features/search/data/search_query_builder.dart';
import 'package:fanotifier/shared/fa/cloudflare_challenge_exception.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';
import 'package:fanotifier/shared/utils/content_rating_filters.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SearchImageService {
  SearchImageService({
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
    required String searchQuery,
    required String cookieHeader,
  }) async {
    final uri = buildFaSearchUri(
      pageNumber: pageNumber,
      selectedFilters: selectedFilters,
      searchQuery: searchQuery,
    );

    final response = await FAHttp.get(
      uri,
      headers: {
        HttpHeaders.cookieHeader:
            await FaCookieHelper.appendCfClearanceToCookieHeader(cookieHeader),
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/search/',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      },
    );

    final refreshedCf = FaCookieHelper.extractCfClearanceFromSetCookieHeader(
      response.headers['set-cookie'],
    );
    if (refreshedCf != null && refreshedCf.isNotEmpty) {
      await FaCookieHelper.writeCfClearance(refreshedCf);
    }

    final isChallenge = FaCookieHelper.isCloudflareChallengePage(
      body: response.body,
      statusCode: response.statusCode,
    );
    if (isChallenge) {
      throw CloudflareChallengeException(initialUrl: uri.toString());
    }

    if (response.statusCode == 200) {
      final faMessage = parseFaSystemMessage(response.body);
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
      return parseSearchImageHtml(response.body);
    }

    throw Exception('Failed to load images: ${response.statusCode}');
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
}
