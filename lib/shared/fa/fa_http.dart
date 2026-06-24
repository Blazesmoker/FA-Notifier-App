import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';

typedef _Call<T> = Future<T> Function();

class FAHttp {
  static const Duration defaultTimeout = Duration(seconds: 20);
  static const String appName = 'FA Notifier';
  static const String _prefsUserAgentKey = 'fa_notifier.userAgent';
  static const String _prefsAppVersionKey = 'fa_notifier.appVersion';

  static String appVersion = '0.0.0';
  static String userAgent = '$appName v0.0.0';

  static HttpClient? _http;
  static IOClient? _client;

  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      if (v.isNotEmpty) {
        appVersion = v;
        userAgent = '$appName v$appVersion';
        reset();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsAppVersionKey, appVersion);
        await prefs.setString(_prefsUserAgentKey, userAgent);
      }
    } catch (_) {}
  }

  static Future<void> initFromPrefs({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final v = (p.getString(_prefsAppVersionKey) ?? '').trim();
      final ua = (p.getString(_prefsUserAgentKey) ?? '').trim();
      if (v.isNotEmpty) appVersion = v;
      if (ua.isNotEmpty) {
        userAgent = ua;
      } else {
        userAgent = '$appName v$appVersion';
      }
      reset();
    } catch (_) {}
  }

  static void reset() {
    try {
      _client?.close();
    } catch (_) {}
    try {
      _http?.close(force: true);
    } catch (_) {}
    _client = null;
    _http = null;
  }

  static IOClient _ensureClient({Duration? timeout}) {
    final t = timeout ?? defaultTimeout;

    if (_client != null) {
      try {
        _http?.connectionTimeout = t;
      } catch (_) {}
      return _client!;
    }

    final c = HttpClient()
      ..connectionTimeout = t
      ..idleTimeout = const Duration(seconds: 10)
      ..autoUncompress = true
      ..maxConnectionsPerHost = 8
      ..userAgent = userAgent;

    _http = c;
    _client = IOClient(c);
    return _client!;
  }

  static bool _isRecoverable(Object e) {
    if (e is http.ClientException) return true;

    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HandshakeException) return true;

    if (e is HttpException) {
      final m = e.message.toLowerCase();
      return m.contains('connection') ||
          m.contains('closed') ||
          m.contains('reset') ||
          m.contains('broken pipe') ||
          m.contains('timed out');
    }

    final s = e.toString().toLowerCase();
    return s.contains('broken pipe') ||
        s.contains('connection reset') ||
        s.contains('timed out') ||
        s.contains('connection closed before full header was received') ||
        s.contains('connection closed while receiving') ||
        s.contains('connection terminated') ||
        s.contains('network is unreachable') ||
        s.contains('software caused connection abort');
  }

  static Map<String, String> _mergeHeaders(Map<String, String>? headers) {
    final out = <String, String>{
      HttpHeaders.acceptEncodingHeader: 'gzip',
      if (headers != null) ...headers,
    };
    out.removeWhere((k, _) => k.toLowerCase() == 'user-agent');
    out['User-Agent'] = userAgent;
    return out;
  }

  static Future<R> _withOneRetry<R>(
    _Call<R> call, {
    bool recordRecoverableFailure = true,
  }) async {
    try {
      return await call();
    } catch (e) {
      if (_isRecoverable(e)) {
        reset();
        if (recordRecoverableFailure) {
          FaRequestCoordinator.instance.recordRecoverableFailure();
        }
        return await call();
      }
      rethrow;
    }
  }

  static Future<http.Response> get(
      Uri uri, {
        Map<String, String>? headers,
        Duration? timeout,
      }) async {
    final t = timeout ?? defaultTimeout;
    return _withOneRetry(() async {
      await FaRequestCoordinator.instance.waitForTurn(
        label: 'GET $uri',
      );
      final c = _ensureClient(timeout: t);
      final response =
          await c.get(uri, headers: _mergeHeaders(headers)).timeout(t);
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        headers: response.headers,
        responseBody: response.statusCode == 403 ? response.body : null,
      );
      return response;
    });
  }

  static Future<http.Response> getMedia(
      Uri uri, {
        Map<String, String>? headers,
        Duration? timeout,
      }) async {
    final t = timeout ?? defaultTimeout;
    return _withOneRetry(
      () async {
        final c = _ensureClient(timeout: t);
        return c.get(uri, headers: _mergeHeaders(headers)).timeout(t);
      },
      recordRecoverableFailure: false,
    );
  }

  static Future<http.Response> post(
      Uri uri, {
        Map<String, String>? headers,
        Object? body,
        Encoding? encoding,
        Duration? timeout,
      }) async {
    final t = timeout ?? defaultTimeout;
    return _withOneRetry(() async {
      await FaRequestCoordinator.instance.waitForTurn(
        label: 'POST $uri',
      );
      final c = _ensureClient(timeout: t);
      final response = await c
          .post(uri, headers: _mergeHeaders(headers), body: body, encoding: encoding)
          .timeout(t);
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        headers: response.headers,
        responseBody: response.statusCode == 403 ? response.body : null,
      );
      return response;
    });
  }
}
