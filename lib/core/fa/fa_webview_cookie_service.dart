import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/fa/fa_media_auth.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FAWebViewCookieService {
  const FAWebViewCookieService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;
  final SfwModePreference _sfwModePreference = const SfwModePreference();
  static const _cookieKeys = [
    'a', 'b', 'cc', 'cf_clearance', 'folder', 'nodesc', 'sz', 'sfw',
  ];

  Future<void> setCookies({
    bool applySfwPreference = true,
    bool preserveExistingSession = false,
    bool preferStoredClearance = false,
  }) async {
    final cookieManager = CookieManager.instance();
    final uri = Uri.parse('https://www.furaffinity.net/');
    final current = _selectCookies(
      await cookieManager.getCookies(url: WebUri(uri.toString())),
      uri,
    );

    for (final key in _cookieKeys) {
      if (key == 'cf_clearance') {
        await _restoreClearance(
          current,
          uri,
          preferStoredClearance: preferStoredClearance,
        );
        continue;
      }
      if (preserveExistingSession && current.containsKey(key)) continue;
      String value;
      if (key == 'sfw' && applySfwPreference) {
        value = await _getSfwCookieValue();
      } else {
        value = await _secureStorage.read(key: 'fa_cookie_$key') ?? '';
      }

      if (value.isNotEmpty) {
        await cookieManager.setCookie(
          url: WebUri('https://www.furaffinity.net'),
          name: key,
          value: value,
          domain: '.furaffinity.net',
          path: '/',
          isSecure: true,
          isHttpOnly: true,
        );
      }
    }
  }

  Future<void> restoreClearance() async {
    final uri = Uri.parse('https://www.furaffinity.net/');
    final current = _selectCookies(
      await CookieManager.instance().getCookies(url: WebUri(uri.toString())),
      uri,
    );
    await _restoreClearance(current, uri);
  }

  Future<void> _restoreClearance(
    Map<String, Cookie> current,
    Uri uri, {
    bool preferStoredClearance = false,
  }) async {
    final existing = current['cf_clearance'];
    if (existing != null && !preferStoredClearance) {
      await _saveClearance(existing);
      return;
    }
    final clearance = await FaCookieHelper.readCfClearance();
    if (clearance == null) return;
    final scope = await FaCookieHelper.readCfClearanceScope();
    final domain = scope?['domain'] as String?;
    final path = scope?['path'] as String? ?? '/';
    if (domain != null && !_matchesDomain(uri.host, domain)) return;
    if (!_matchesPath(uri.path, path)) return;
    await CookieManager.instance().setCookie(
      url: WebUri(uri.toString()),
      name: 'cf_clearance',
      value: clearance,
      domain: scope == null ? '.furaffinity.net' : domain,
      path: path,
      expiresDate: (scope?['expiresDate'] as num?)?.toInt(),
      isSecure: scope?['isSecure'] as bool? ?? true,
      isHttpOnly: scope?['isHttpOnly'] as bool? ?? true,
      sameSite: HTTPCookieSameSitePolicy.fromValue(scope?['sameSite'] as String?),
    );
  }

  Future<bool> captureCookies({
    required String url,
    Future<Object?> Function(String source)? evaluateJavascript,
    bool Function()? isCancelled,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        (uri.host != 'www.furaffinity.net' &&
            uri.host != 'furaffinity.net')) {
      return false;
    }
    final selected = _selectCookies(
      await CookieManager.instance().getCookies(url: WebUri(url)),
      uri,
    );
    if (isCancelled?.call() ?? false) return false;
    final values = <String, String>{
      for (final entry in selected.entries) entry.key: entry.value.value,
    };
    if (evaluateJavascript != null) {
      try {
        final raw = await evaluateJavascript('document.cookie');
        if (raw is String) {
          for (final pair in raw.split(';')) {
            final separator = pair.indexOf('=');
            if (separator <= 0) continue;
            final name = pair.substring(0, separator).trim();
            final value = pair.substring(separator + 1).trim();
            if (_cookieKeys.contains(name) && value.isNotEmpty) {
              values.putIfAbsent(name, () => value);
            }
          }
        }
      } catch (_) {}
    }
    if (isCancelled?.call() ?? false) return false;

    var changed = false;
    try {
      for (final entry in values.entries) {
        if (entry.key == 'cf_clearance') continue;
        final key = 'fa_cookie_${entry.key}';
        if (await _secureStorage.read(key: key) == entry.value) continue;
        if (isCancelled?.call() ?? false) return false;
        await _secureStorage.write(key: key, value: entry.value);
        changed = true;
      }
      if (isCancelled?.call() ?? false) return false;
      final clearance = selected['cf_clearance'];
      final value = values['cf_clearance'];
      if (clearance != null) {
        await _saveClearance(clearance);
      } else if (value != null) {
        await FaCookieHelper.writeCfClearance(value);
      }
      return values.containsKey('cf_clearance');
    } finally {
      if (changed) FaMediaAuth.invalidate();
    }
  }

  Future<void> _saveClearance(Cookie cookie) {
    return FaCookieHelper.writeCfClearance(
      cookie.value,
      scope: cookie.domain == null
          ? null
          : {
              'domain': cookie.domain,
              'path': cookie.path ?? '/',
              'expiresDate': cookie.expiresDate,
              'isSecure': cookie.isSecure,
              'isHttpOnly': cookie.isHttpOnly,
              'sameSite': cookie.sameSite?.toValue(),
            },
    );
  }

  Map<String, Cookie> _selectCookies(List<Cookie> cookies, Uri uri) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final applicable = cookies.where((cookie) {
      return _cookieKeys.contains(cookie.name) &&
          cookie.value.isNotEmpty &&
          (cookie.expiresDate == null || cookie.expiresDate! > now) &&
          (cookie.domain == null || _matchesDomain(uri.host, cookie.domain!)) &&
          _matchesPath(uri.path, cookie.path ?? '/');
    }).toList();
    applicable.sort((a, b) {
      final pathOrder = (b.path ?? '/').length.compareTo((a.path ?? '/').length);
      if (pathOrder != 0) return pathOrder;
      final aExact = a.domain == uri.host ? 1 : 0;
      final bExact = b.domain == uri.host ? 1 : 0;
      final domainOrder = bExact.compareTo(aExact);
      if (domainOrder != 0) return domainOrder;
      return (b.expiresDate ?? 0).compareTo(a.expiresDate ?? 0);
    });
    final selected = <String, Cookie>{};
    for (final cookie in applicable) {
      selected.putIfAbsent(cookie.name, () => cookie);
    }
    return selected;
  }

  bool _matchesDomain(String host, String domain) {
    final normalized = domain.startsWith('.') ? domain.substring(1) : domain;
    return host == normalized ||
        (domain.startsWith('.') && host.endsWith('.$normalized'));
  }

  bool _matchesPath(String requestPath, String cookiePath) {
    final path = requestPath.isEmpty ? '/' : requestPath;
    return path == cookiePath ||
        (path.startsWith(cookiePath) &&
            (cookiePath.endsWith('/') ||
                path.substring(cookiePath.length).startsWith('/')));
  }

  Future<String> _getSfwCookieValue() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    return sfwEnabled ? '1' : '0';
  }
}
