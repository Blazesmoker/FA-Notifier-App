import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StartupCloudflareCheckResult {
  const StartupCloudflareCheckResult({
    required this.needsChallenge,
    this.homeHtml,
  });

  final bool needsChallenge;
  final String? homeHtml;
}

class StartupCloudflareCheckService {
  const StartupCloudflareCheckService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<bool> needsChallenge({
    String url = 'https://www.furaffinity.net/',
  }) async {
    final result = await checkHome(url: url);
    return result.needsChallenge;
  }

  Future<StartupCloudflareCheckResult> checkHome({
    String url = 'https://www.furaffinity.net/',
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final rawCookieHeader =
        (cookieA != null && cookieB != null) ? 'a=$cookieA; b=$cookieB' : '';
    final cookieHeader =
        await FaCookieHelper.appendCfClearanceToCookieHeader(rawCookieHeader);
    final headers = <String, String>{
      'User-Agent': FAHttp.userAgent,
    };
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    try {
      final response = await FAHttp.get(
        Uri.parse(url),
        headers: headers,
      );

      final refreshedCf = FaCookieHelper.extractCfClearanceFromSetCookieHeader(
        response.headers['set-cookie'],
      );
      if (refreshedCf != null && refreshedCf.isNotEmpty) {
        await FaCookieHelper.writeCfClearance(refreshedCf);
      }

      final needsChallenge = FaCookieHelper.isCloudflareChallengePage(
        body: response.body,
        statusCode: response.statusCode,
      );
      return StartupCloudflareCheckResult(
        needsChallenge: needsChallenge,
        homeHtml: needsChallenge ? null : response.body,
      );
    } catch (e) {
      debugPrint('[Cloudflare] Startup check request failed: $e');
      return const StartupCloudflareCheckResult(needsChallenge: false);
    }
  }
}
