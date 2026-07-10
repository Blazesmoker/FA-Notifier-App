import 'dart:io';

import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CloudflareHttpAccessVerifier {
  const CloudflareHttpAccessVerifier({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  String get userAgent => FAHttp.userAgent;

  Future<bool> verify({
    required String url,
    Future<void> Function()? beforeRetryAttempt,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 250 * attempt));
        await beforeRetryAttempt?.call();
      }

      final cookieHeader = await FaCookieHelper.appendCfClearanceToCookieHeader(
        await _getCookieHeader(),
      );
      try {
        final response = await FAHttp.get(
          uri,
          headers: {
            if (cookieHeader.isNotEmpty) HttpHeaders.cookieHeader: cookieHeader,
            'User-Agent': FAHttp.userAgent,
            'Referer': 'https://www.furaffinity.net/',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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
        debugPrint(
          '[Cloudflare] HTTP verification attempt ${attempt + 1} for $url => '
          'status=${response.statusCode}, challenge=$isChallenge',
        );
        if (!isChallenge) {
          return true;
        }
      } catch (e) {
        debugPrint(
          '[Cloudflare] HTTP verification attempt ${attempt + 1} failed: $e',
        );
      }
    }

    return false;
  }

  Future<String> _getCookieHeader() async {
    const cookieKeys = <String>[
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
    for (final key in cookieKeys) {
      final value = await _secureStorage.read(key: 'fa_cookie_$key');
      if (value != null && value.isNotEmpty) {
        cookies.add('$key=$value');
      }
    }
    return cookies.join('; ');
  }
}
