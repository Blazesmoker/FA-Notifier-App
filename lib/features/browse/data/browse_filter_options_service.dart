import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/features/browse/data/browse_filter_options_parser.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

Future<Map<String, List<Map<String, String>>>> fetchBrowseFilterOptions({
  FlutterSecureStorage? secureStorage,
}) async {
  try {
    debugPrint('Fetching all filters...');
    final cookieHeader = await _buildCookieHeader(
      secureStorage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accountName: 'flutter_secure_storage_service',
              accessibility: KeychainAccessibility.first_unlock,
            ),
          ),
    );
    final response = await FAHttp.get(
      Uri.parse('https://www.furaffinity.net/browse/'),
      headers: {
        if (cookieHeader.isNotEmpty) HttpHeaders.cookieHeader: cookieHeader,
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/browse/',
      },
    );

    final refreshedCf = FaCookieHelper.extractCfClearanceFromSetCookieHeader(
      response.headers['set-cookie'],
    );
    if (refreshedCf != null && refreshedCf.isNotEmpty) {
      await FaCookieHelper.writeCfClearance(refreshedCf);
    }

    if (response.statusCode == 200) {
      final loadedFilterOptions = parseBrowseFilterOptions(response.body);
      for (final entry in loadedFilterOptions.entries) {
        if (entry.value.isNotEmpty) {
          debugPrint('${entry.key}: ${entry.value.length} options fetched.');
        } else {
          debugPrint('Select element for "${entry.key}" not found.');
        }
      }
      return loadedFilterOptions;
    }

    debugPrint('Failed to fetch filters. Status code: ${response.statusCode}');
    return emptyBrowseFilterOptions();
  } catch (e) {
    debugPrint('Error fetching filter data: $e');
    return emptyBrowseFilterOptions();
  }
}

Future<String> _buildCookieHeader(FlutterSecureStorage secureStorage) async {
  final cookieNames = [
    'a',
    'b',
    'cc',
    'cf_clearance',
    'folder',
    'nodesc',
    'sz',
    'sfw',
  ];
  final cookies = <String>[];
  for (final name in cookieNames) {
    final value = await secureStorage.read(key: 'fa_cookie_$name');
    if (value != null && value.isNotEmpty) {
      cookies.add('$name=$value');
    }
  }
  return FaCookieHelper.appendCfClearanceToCookieHeader(cookies.join('; '));
}

Map<String, List<Map<String, String>>> emptyBrowseFilterOptions() => {
      'cat': [],
      'atype': [],
      'species': [],
      'gender': [],
    };
