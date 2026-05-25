import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/shared/fa/fa_media_auth.dart';

class FaCookieHelper {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _cfKey = 'fa_cookie_cf_clearance';

  static Future<String?> readCfClearance() async {
    final value = await _secureStorage.read(key: _cfKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  static Future<void> writeCfClearance(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    await _secureStorage.write(key: _cfKey, value: trimmed);
    FaMediaAuth.invalidate();
  }

  static Future<String> appendCfClearanceToCookieHeader(String cookieHeader) async {
    final trimmed = cookieHeader.trim().replaceAll(RegExp(r';\s*$'), '');
    if (trimmed.contains('cf_clearance=')) {
      return trimmed;
    }
    final cfClearance = await readCfClearance();
    if (cfClearance == null || cfClearance.isEmpty) {
      return trimmed;
    }
    if (trimmed.isEmpty) {
      return 'cf_clearance=$cfClearance';
    }
    return '$trimmed; cf_clearance=$cfClearance';
  }

  static Future<List<Cookie>> addCfClearanceCookie(List<Cookie> cookies) async {
    final hasCf = cookies.any((cookie) => cookie.name == 'cf_clearance');
    if (hasCf) {
      return cookies;
    }
    final cfClearance = await readCfClearance();
    if (cfClearance == null || cfClearance.isEmpty) {
      return cookies;
    }
    return <Cookie>[
      ...cookies,
      Cookie('cf_clearance', cfClearance),
    ];
  }

  static bool isCloudflareChallengePage({
    required String body,
    int? statusCode,
  }) {
    final lower = body.toLowerCase();
    if (statusCode == 403 && lower.contains('cloudflare')) {
      return true;
    }
    return lower.contains('<title>just a moment...</title>') ||
        lower.contains('cf-turnstile-response') ||
        lower.contains('/cdn-cgi/challenge-platform') ||
        lower.contains('verify you are human') ||
        lower.contains('needs to review the security of your connection');
  }

  static String? extractCfClearanceFromSetCookieHeader(String? setCookieHeader) {
    if (setCookieHeader == null || setCookieHeader.isEmpty) {
      return null;
    }
    final match = RegExp(r'cf_clearance=([^;,\s]+)').firstMatch(setCookieHeader);
    if (match == null) {
      return null;
    }
    final value = match.group(1);
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}
