import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';

class FaNotificationCookieHeaderProvider {
  const FaNotificationCookieHeaderProvider();

  Future<String?> load() async {
    try {
      final cookieA = await const FlutterSecureStorage(
        iOptions: IOSOptions(
          accountName: 'flutter_secure_storage_service',
          accessibility: KeychainAccessibility.first_unlock,
        ),
      ).read(key: 'fa_cookie_a');
      final cookieB = await const FlutterSecureStorage(
        iOptions: IOSOptions(
          accountName: 'flutter_secure_storage_service',
          accessibility: KeychainAccessibility.first_unlock,
        ),
      ).read(key: 'fa_cookie_b');
      final sfwEnabled = await const SfwModePreference().loadSfwEnabled();
      var cookieHeader = '';
      if (cookieA != null && cookieA.isNotEmpty) {
        cookieHeader += 'a=$cookieA; ';
      }
      if (cookieB != null && cookieB.isNotEmpty) {
        cookieHeader += 'b=$cookieB; ';
      }
      if (sfwEnabled) {
        cookieHeader += 'sfw=1;';
      }
      cookieHeader = cookieHeader.trim();
      cookieHeader =
          await FaCookieHelper.appendCfClearanceToCookieHeader(cookieHeader);
      debugPrint('[_getCookieHeader] cookie header built');
      return cookieHeader;
    } catch (error) {
      debugPrint('[_getCookieHeader] Error reading cookies: $error');
    }
    return null;
  }
}
