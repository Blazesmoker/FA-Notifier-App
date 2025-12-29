import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef _Call<T> = Future<T> Function();

class FAHttp {
  static const Duration defaultTimeout = Duration(seconds: 20);

  static HttpClient? _http;
  static IOClient? _client;

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
      ..userAgent = 'FANotifier/1.0 (+dart:io)';

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
    return <String, String>{
      HttpHeaders.acceptEncodingHeader: 'gzip',
      if (headers != null) ...headers,
    };
  }

  static Future<R> _withOneRetry<R>(_Call<R> call) async {
    try {
      return await call();
    } catch (e) {
      if (e is Object && _isRecoverable(e)) {
        reset();
        await Future.delayed(const Duration(milliseconds: 250));
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
      final c = _ensureClient(timeout: t);
      return await c.get(uri, headers: _mergeHeaders(headers)).timeout(t);
    });
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
      final c = _ensureClient(timeout: t);
      return await c
          .post(uri, headers: _mergeHeaders(headers), body: body, encoding: encoding)
          .timeout(t);
    });
  }
}
