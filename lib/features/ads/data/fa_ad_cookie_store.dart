import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/core/fa/fa_media_auth.dart';
import 'package:fanotifier/core/logging/fa_ads_logging.dart';

class FaAdCookieStore {
  FaAdCookieStore({FlutterSecureStorage? secureStorage})
      : _storage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;
  static const _sessionKeys = ['a', 'b', 'n', 'cf_clearance', 'folder', 'nodesc'];
  final Map<String, _AdCookie> _received = {};
  final Set<String> _deleted = {};
  Future<void> _writes = Future<void>.value();
  int _epoch = 0;

  Future<FaAdCookieHeader> prepareHeader(Uri uri, {required bool sfwEnabled}) async {
    final epoch = _epoch;
    await _writes.catchError((_) {});
    final eligible = <_AdCookie>[];
    var rejected = 0;
    var unknownMetadata = 0;
    final cookies = await webview.CookieManager.instance().getCookies(
      url: webview.WebUri(uri.replace(query: '', fragment: '').toString()),
    );
    for (final cookie in cookies) {
      if (cookie.name == 'sfw') continue;
      if (uri.host != 'www.furaffinity.net' &&
          (cookie.name == 'cc' || cookie.name == 'sz')) {
        rejected++;
        continue;
      }
      if (cookie.domain == null) unknownMetadata++;
      final domain = cookie.domain ??
          (_sessionKeys.contains(cookie.name) ? 'furaffinity.net' : uri.host);
      final entry = _AdCookie(
        name: cookie.name,
        value: cookie.value.toString(),
        domain: domain.replaceFirst(RegExp(r'^\.'), '').toLowerCase(),
        hostOnly: !domain.startsWith('.') && domain != 'furaffinity.net',
        path: cookie.path ?? '/',
        secure: cookie.isSecure ?? true,
        expires: cookie.expiresDate == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!),
      );
      if (entry.matches(uri)) {
        eligible.add(entry);
      } else {
        rejected++;
      }
    }
    for (final entry in _received.values) {
      if (entry.name == 'sfw' || !entry.matches(uri)) continue;
      eligible.removeWhere((cookie) => cookie.key == entry.key);
      eligible.add(entry);
    }
    var legacy = 0;
    for (final name in _sessionKeys) {
      if (eligible.any((cookie) => cookie.name == name)) continue;
      final value = await _storage.read(key: 'fa_cookie_$name');
      if (value == null || value.isEmpty) continue;
      eligible.add(_AdCookie(
        name: name,
        value: value,
        domain: 'furaffinity.net',
        hostOnly: false,
        path: '/',
        secure: true,
      ));
      legacy++;
    }
    if (epoch != _epoch) throw StateError('Ad session ended');
    return FaAdCookieHeader._(() {
      if (epoch != _epoch) throw StateError('Ad session ended');
      final current = eligible.where((cookie) =>
          !_deleted.contains(cookie.key) && cookie.matches(uri)).toList();
      for (final entry in _received.values) {
        if (entry.name == 'sfw' || !entry.matches(uri)) continue;
        current.removeWhere((cookie) => cookie.key == entry.key);
        current.add(entry);
      }
      current.sort((a, b) => b.path.length.compareTo(a.path.length));
      FaAdsLog.event(FaAdsLogCategory.cookie, 'request_scope_checked',
        counts: {
          'selected': current.length,
          'legacyFallback': legacy,
          'rejectedScope': rejected,
          'unknownMetadata': unknownMetadata,
        },
        checks: {
          'modeMatchesPage': true,
          'adCookiePresent': current.any((cookie) => cookie.name == 'OAID'),
          'authCookiesPresent': current.any((cookie) => cookie.name == 'a') &&
              current.any((cookie) => cookie.name == 'b'),
        });
      return [
        for (final cookie in current) '${cookie.name}=${cookie.value}',
        if (sfwEnabled) 'sfw=1',
      ].join('; ');
    });
  }

  Future<void> storeResponse(Uri uri, List<String> setCookies) {
    final epoch = _epoch;
    final next = _writes.catchError((_) {}).then((_) async {
      for (final raw in setCookies) {
        if (epoch != _epoch) return;
        try {
          final parsed = Cookie.fromSetCookieValue(raw);
          final hostOnly = parsed.domain == null;
          final domain = (parsed.domain ?? uri.host)
              .replaceFirst(RegExp(r'^\.'), '').toLowerCase();
          if (domain != uri.host && !uri.host.endsWith('.$domain')) continue;
          if (domain != 'furaffinity.net' && !domain.endsWith('.furaffinity.net')) {
            continue;
          }
          final slash = uri.path.lastIndexOf('/');
          final defaultPath = slash > 0 ? uri.path.substring(0, slash) : '/';
          final path = parsed.path?.startsWith('/') == true
              ? parsed.path!
              : defaultPath;
          final expiry = parsed.maxAge != null
              ? DateTime.now().add(Duration(seconds: parsed.maxAge!))
              : parsed.expires;
          final entry = _AdCookie(
            name: parsed.name,
            value: parsed.value,
            domain: domain,
            hostOnly: hostOnly,
            path: path,
            secure: parsed.secure,
            expires: expiry,
          );
          final expired = expiry != null && !expiry.isAfter(DateTime.now());
          webview.HTTPCookieSameSitePolicy? sameSite;
          for (final attribute in raw.split(';').skip(1)) {
            final value = attribute.trim().toLowerCase();
            if (value == 'samesite=none') {
              sameSite = webview.HTTPCookieSameSitePolicy.NONE;
            } else if (value == 'samesite=lax') {
              sameSite = webview.HTTPCookieSameSitePolicy.LAX;
            } else if (value == 'samesite=strict') {
              sameSite = webview.HTTPCookieSameSitePolicy.STRICT;
            }
          }
          if (sameSite == webview.HTTPCookieSameSitePolicy.NONE && !parsed.secure) {
            continue;
          }
          bool jarUpdated;
          if (expired) {
            _received.remove(entry.key);
            _deleted.add(entry.key);
            jarUpdated = await webview.CookieManager.instance().deleteCookie(
              url: webview.WebUri(uri.replace(query: '', fragment: '').toString()),
              name: parsed.name,
              domain: hostOnly ? null : parsed.domain,
              path: path,
            );
          } else {
            _deleted.remove(entry.key);
            _received[entry.key] = entry;
            jarUpdated = await webview.CookieManager.instance().setCookie(
              url: webview.WebUri(uri.replace(query: '', fragment: '').toString()),
              name: parsed.name,
              value: parsed.value,
              domain: hostOnly ? null : parsed.domain,
              path: path,
              expiresDate: expiry?.millisecondsSinceEpoch,
              isSecure: parsed.secure,
              isHttpOnly: parsed.httpOnly,
              sameSite: sameSite,
            );
          }
          if (epoch != _epoch) return;
          if (domain == 'furaffinity.net' && path == '/' && !hostOnly &&
              _sessionKeys.contains(parsed.name)) {
            if (expired) {
              await _storage.delete(key: 'fa_cookie_${parsed.name}');
            } else {
              await _storage.write(key: 'fa_cookie_${parsed.name}', value: parsed.value);
            }
          }
          if (epoch != _epoch) return;
          FaMediaAuth.invalidate();
          FaAdsLog.event(FaAdsLogCategory.cookie, 'response_cookie_applied',
              checks: {
                'hostOnly': hostOnly,
                'secure': parsed.secure,
                'httpOnly': parsed.httpOnly,
                'hasExpiry': expiry != null,
                'deleted': expired,
                'sameSiteNone': sameSite == webview.HTTPCookieSameSitePolicy.NONE,
                'jarUpdated': jarUpdated,
              });
        } catch (_) {
          FaAdsLog.event(FaAdsLogCategory.cookie, 'response_cookie_rejected');
        }
      }
    });
    _writes = next;
    return next;
  }

  Future<void> reset() async {
    _epoch++;
    _received.clear();
    _deleted.clear();
    await _writes.catchError((_) {});
  }
}

class FaAdCookieHeader {
  const FaAdCookieHeader._(this._read);

  final String Function() _read;

  String get value => _read();
}

class _AdCookie {
  const _AdCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.hostOnly,
    required this.path,
    required this.secure,
    this.expires,
  });

  final String name;
  final String value;
  final String domain;
  final bool hostOnly;
  final String path;
  final bool secure;
  final DateTime? expires;

  String get key => '$name|$domain|$path';

  bool matches(Uri uri) {
    if (secure && uri.scheme != 'https') return false;
    if (expires != null && !expires!.isAfter(DateTime.now())) return false;
    if (hostOnly ? uri.host != domain :
        uri.host != domain && !uri.host.endsWith('.$domain')) {
      return false;
    }
    return uri.path == path ||
        (uri.path.startsWith(path) &&
            (path.endsWith('/') || uri.path.substring(path.length).startsWith('/')));
  }
}
