import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef _Call<T> = Future<T> Function();

class FAHttp {
  static const Duration _defaultTimeout = Duration(seconds: 20);

  // Heuristics for stale/broken sockets after backgrounding
  static bool _looksLikeStaleSocket(Object e) {
    final s = e.toString();
    return e is SocketException ||
        s.contains('Broken pipe') ||
        s.contains('Connection reset') ||
        s.contains('timed out') ||
        s.contains('Connection closed while receiving');
  }

  static Future<R> _withRetry<R>(_Call<R> call) async {
    try {
      return await call();
    } catch (e) {
      if (_looksLikeStaleSocket(e)) {
        // Give iOS a breath to re-warm radios, then try once fresh
        await Future.delayed(const Duration(milliseconds: 250));
        return await call();
      }
      rethrow;
    }
  }

  static HttpClient _newClientBase({Duration? timeout}) {
    final c = HttpClient();
    c.connectionTimeout = timeout ?? _defaultTimeout;
    c.idleTimeout = Duration.zero; // don't keep sockets around
    c.userAgent = 'FANotifier/1.0 (+dart:io)';
    return c;
  }

  static Future<http.Response> get(
      Uri uri, {
        Map<String, String>? headers,
        Duration? timeout,
      }) async {
    return _withRetry(() async {
      final client = IOClient(_newClientBase(timeout: timeout));
      try {
        final merged = {
          HttpHeaders.connectionHeader: 'close',
          if (headers != null) ...headers,
        };
        final resp = await client.get(uri, headers: merged).timeout(timeout ?? _defaultTimeout);
        return resp;
      } finally {
        client.close(); // drop the socket pool every time
      }
    });
  }

  static Future<http.Response> post(
      Uri uri, {
        Map<String, String>? headers,
        Object? body,
        Encoding? encoding,
        Duration? timeout,
      }) async {
    return _withRetry(() async {
      final client = IOClient(_newClientBase(timeout: timeout));
      try {
        final merged = {
          HttpHeaders.connectionHeader: 'close',
          if (headers != null) ...headers,
        };
        final resp = await client
            .post(uri, headers: merged, body: body, encoding: encoding)
            .timeout(timeout ?? _defaultTimeout);
        return resp;
      } finally {
        client.close();
      }
    });
  }
}
