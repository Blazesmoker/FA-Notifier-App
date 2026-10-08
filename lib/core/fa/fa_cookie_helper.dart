import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/core/fa/fa_media_auth.dart';

class FaCookieHelper {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _cfKey = 'fa_cookie_cf_clearance';
  static const String _cfScopeKey = 'fa_cookie_cf_clearance_scope_v1';
  static Future<void> _clearanceWrites = Future<void>.value();

  static Future<String?> readCfClearance({Uri? uri}) async {
    final value = await _secureStorage.read(key: _cfKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final trimmed = value.trim();
    final scope = await _readCfClearanceScope(trimmed);
    if (!isClearanceApplicable(scope, uri: uri)) return null;
    return trimmed;
  }

  static bool isClearanceApplicable(
    Map<String, dynamic>? scope, {
    Uri? uri,
  }) {
    final expiresDate = scope?['expiresDate'];
    if (expiresDate is num &&
        expiresDate <= DateTime.now().millisecondsSinceEpoch) {
      return false;
    }
    if (uri != null && scope != null) {
      final domain = scope['domain'] as String?;
      final path = scope['path'] as String? ?? '/';
      final host = uri.host.toLowerCase();
      if (domain != null) {
        final normalized = domain.toLowerCase();
        final bare = normalized.startsWith('.')
            ? normalized.substring(1)
            : normalized;
        if (host != bare &&
            !(normalized.startsWith('.') && host.endsWith('.$bare'))) {
          return false;
        }
      }
      final requestPath = uri.path.isEmpty ? '/' : uri.path;
      if (requestPath != path &&
          !(requestPath.startsWith(path) &&
              (path.endsWith('/') ||
                  requestPath.substring(path.length).startsWith('/')))) {
        return false;
      }
      if (scope['isSecure'] == true && uri.scheme != 'https') return false;
    }
    return true;
  }

  static Future<Map<String, dynamic>?> _readCfClearanceScope(String value) async {
    final raw = await _secureStorage.read(key: _cfScopeKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['version'] == 1 &&
          decoded['value'] == value) {
        return decoded;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> readCfClearanceScope() async {
    final value = await readCfClearance();
    return value == null ? null : _readCfClearanceScope(value);
  }

  static Future<void> clearCfClearanceForUri(Uri uri) {
    final operation = _clearanceWrites.catchError((_) {}).then(
      (_) => _clearCfClearanceForUri(uri),
    );
    _clearanceWrites = operation;
    return operation;
  }

  static Future<void> _clearCfClearanceForUri(Uri uri) async {
    final value = await _secureStorage.read(key: _cfKey);
    if (value == null) return;
    final scope = await _readCfClearanceScope(value.trim());
    if (!isClearanceApplicable(
      scope == null ? null : {...scope, 'expiresDate': null},
      uri: uri,
    )) {
      return;
    }
    await _secureStorage.delete(key: _cfKey);
    await _secureStorage.delete(key: _cfScopeKey);
    FaMediaAuth.invalidate();
  }

  static Future<void> acceptCfClearanceHeaders({
    required Uri uri,
    required Iterable<String> headers,
  }) async {
    if (uri.scheme != 'https' ||
        !(uri.host == 'furaffinity.net' ||
            uri.host.endsWith('.furaffinity.net'))) {
      return;
    }
    for (final header in headers.expand(
      (value) => value.split(RegExp(r',(?=\s*[A-Za-z0-9_-]+\s*=)')),
    )) {
      try {
        final cookie = Cookie.fromSetCookieValue(header);
        if (cookie.name != 'cf_clearance') continue;
        final slash = uri.path.lastIndexOf('/');
        final sameSite = RegExp(
          r'(?:^|;)\s*samesite\s*=\s*(none|lax|strict)\s*(?:;|$)',
          caseSensitive: false,
        ).firstMatch(header)?.group(1)?.toLowerCase();
        final scope = <String, Object?>{
          'domain': cookie.domain ?? uri.host,
          'path': cookie.path?.startsWith('/') == true
              ? cookie.path
              : slash > 0 ? uri.path.substring(0, slash) : '/',
          'expiresDate': cookie.maxAge == null
              ? cookie.expires?.millisecondsSinceEpoch
              : DateTime.now()
                  .add(Duration(seconds: cookie.maxAge!))
                  .millisecondsSinceEpoch,
          'isSecure': cookie.secure,
          'isHttpOnly': cookie.httpOnly,
          'sameSite': sameSite == null
              ? null
              : '${sameSite[0].toUpperCase()}${sameSite.substring(1)}',
        };
        if (!isClearanceApplicable(
          {...scope, 'expiresDate': null},
          uri: uri,
        )) {
          continue;
        }
        if (cookie.value.isEmpty ||
            !isClearanceApplicable(scope, uri: uri)) {
          await clearCfClearanceForUri(uri);
          continue;
        }
        await writeCfClearance(cookie.value, scope: scope);
      } catch (_) {}
    }
  }

  static Future<void> writeCfClearance(
    String value, {
    Map<String, Object?>? scope,
  }) {
    final operation = _clearanceWrites.catchError((_) {}).then(
      (_) => _writeCfClearance(value, scope: scope),
    );
    _clearanceWrites = operation;
    return operation;
  }

  static Future<void> _writeCfClearance(
    String value, {
    Map<String, Object?>? scope,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final previous = await _secureStorage.read(key: _cfKey);
    var scopeChanged = false;
    if (scope != null) {
      final encoded = jsonEncode({...scope, 'version': 1, 'value': trimmed});
      scopeChanged = await _secureStorage.read(key: _cfScopeKey) != encoded;
      if (scopeChanged) {
        await _secureStorage.write(key: _cfScopeKey, value: encoded);
      }
    } else if (previous != trimmed) {
      await _secureStorage.delete(key: _cfScopeKey);
    }
    if (previous == trimmed) {
      if (scopeChanged) FaMediaAuth.invalidate();
      return;
    }
    await _secureStorage.write(key: _cfKey, value: trimmed);
    FaMediaAuth.invalidate();
  }

  static Future<String> appendCfClearanceToCookieHeader(
    String cookieHeader, {
    Uri? uri,
  }) async {
    final trimmed = cookieHeader
        .split(';')
        .map((cookie) => cookie.trim())
        .where((cookie) => cookie.isNotEmpty &&
            cookie.split('=').first.trim() != 'cf_clearance')
        .join('; ');
    final cfClearance = await readCfClearance(uri: uri);
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
    Map<String, dynamic>? headers,
  }) {
    if (headers != null) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() != 'cf-mitigated') continue;
        final value = entry.value;
        if (value is Iterable
            ? value.any((item) => item.toString().toLowerCase() == 'challenge')
            : value.toString().toLowerCase() == 'challenge') {
          return true;
        }
      }
    }
    final lower = body.toLowerCase();
    return lower.contains('<title>just a moment...</title>') ||
        lower.contains('id="challenge-form"') ||
        lower.contains("id='challenge-form'") ||
        lower.contains('window._cf_chl_opt') ||
        ((statusCode == 403 || statusCode == 503) &&
            lower.contains('/cdn-cgi/challenge-platform/'));
  }

  static bool isFaDocument({
    required String body,
    int? statusCode,
    Map<String, dynamic>? headers,
  }) {
    if (body.trim().isEmpty ||
        (statusCode != null &&
            (statusCode < 200 || statusCode >= 300) &&
            statusCode != 304) ||
        isCloudflareChallengePage(
          body: body,
          statusCode: statusCode,
          headers: headers,
        )) {
      return false;
    }
    final document = html_parser.parse(body);
    final title = document.querySelector('title')?.text.toLowerCase() ?? '';
    return title.contains('fur affinity') &&
        document.querySelector(
              '#main-window, #site-content, #header, #footer',
            ) !=
            null;
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
