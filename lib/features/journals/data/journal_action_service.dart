import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class JournalActionService {
  const JournalActionService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<int?> deleteJournal({
    required String deleteLink,
    required String journalId,
  }) {
    return _get(
      deleteLink,
      referer: 'https://www.furaffinity.net/journal/$journalId/',
    );
  }

  Future<int?> sendWatchRequest(String urlPath) {
    return _get('https://www.furaffinity.net$urlPath');
  }

  Future<int?> updateCommentVisibility(String url) {
    return _get(url);
  }

  Future<int?> _get(String url, {String? referer}) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      return null;
    }

    final headers = {
      'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
        'a=$cookieA; b=$cookieB',
      ),
      'User-Agent': FAHttp.userAgent,
    };
    if (referer != null) {
      headers['Referer'] = referer;
    }

    final response = await FAHttp.get(
      Uri.parse(url),
      headers: headers,
    );
    return response.statusCode;
  }
}
