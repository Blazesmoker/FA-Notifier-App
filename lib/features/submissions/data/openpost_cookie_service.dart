import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OpenPostCookieService {
  const OpenPostCookieService({
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
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    return cookieA != null && cookieB != null;
  }

  Future<String> buildCookieHeader({
    required bool sfwEnabled,
    required bool nsfwAllowed,
    bool skipSfw = false,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    var cookieHeader = '';
    if (cookieA != null && cookieB != null) {
      cookieHeader = 'a=$cookieA; b=$cookieB';
    }

    if (!skipSfw && sfwEnabled && !nsfwAllowed) {
      cookieHeader += '; sfw=1';
    }

    return cookieHeader;
  }
}
