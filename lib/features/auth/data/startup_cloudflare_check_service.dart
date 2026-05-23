import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class StartupCloudflareCheckService {
  const StartupCloudflareCheckService({
    required FlutterSecureStorage secureStorage,
  }) : _secureStorage = secureStorage;

  final FlutterSecureStorage _secureStorage;

  Future<bool> needsChallenge({
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

    http.Response response;
    try {
      response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
    } catch (e) {
      debugPrint('[Cloudflare] Startup check request failed: $e');
      return false;
    }

    final refreshedCf = FaCookieHelper.extractCfClearanceFromSetCookieHeader(
      response.headers['set-cookie'],
    );
    if (refreshedCf != null && refreshedCf.isNotEmpty) {
      await FaCookieHelper.writeCfClearance(refreshedCf);
    }

    return FaCookieHelper.isCloudflareChallengePage(
      body: response.body,
      statusCode: response.statusCode,
    );
  }
}
