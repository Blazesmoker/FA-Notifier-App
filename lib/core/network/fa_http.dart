import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/core/network/fa_request_coordinator.dart';

typedef _Call<T> = Future<T> Function();

class FAHttpResolvedResponse {
  const FAHttpResolvedResponse({
    required this.response,
    required this.resolvedUri,
  });

  final http.Response response;
  final Uri resolvedUri;
}

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
      final version = info.version.trim();
      if (version.isNotEmpty) {
        appVersion = version;
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
      final preferences = prefs ?? await SharedPreferences.getInstance();
      final version = (preferences.getString(_prefsAppVersionKey) ?? '').trim();
      final storedUserAgent = (preferences.getString(_prefsUserAgentKey) ?? '').trim();
      if (version.isNotEmpty) appVersion = version;
      if (storedUserAgent.isNotEmpty) {
        userAgent = storedUserAgent;
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
    final requestTimeout = timeout ?? defaultTimeout;

    if (_client != null) {
      try {
        _http?.connectionTimeout = requestTimeout;
      } catch (_) {}
      return _client!;
    }

    final client = HttpClient()
      ..connectionTimeout = requestTimeout
      ..idleTimeout = const Duration(seconds: 10)
      ..autoUncompress = true
      ..maxConnectionsPerHost = 8
      ..userAgent = userAgent;

    _http = client;
    _client = IOClient(client);
    return _client!;
  }

  static bool _isRecoverable(Object e) {
    if (e is http.ClientException) return true;

    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HandshakeException) return true;

    if (e is HttpException) {
      final message = e.message.toLowerCase();
      return message.contains('connection') ||
          message.contains('closed') ||
          message.contains('reset') ||
          message.contains('broken pipe') ||
          message.contains('timed out');
    }

    final errorText = e.toString().toLowerCase();
    return errorText.contains('broken pipe') ||
        errorText.contains('connection reset') ||
        errorText.contains('timed out') ||
        errorText.contains('connection closed before full header was received') ||
        errorText.contains('connection closed while receiving') ||
        errorText.contains('connection terminated') ||
        errorText.contains('network is unreachable') ||
        errorText.contains('software caused connection abort');
  }

  static Map<String, String> _mergeHeaders(Map<String, String>? headers) {
    final out = <String, String>{
      HttpHeaders.acceptEncodingHeader: 'gzip',
      ...?headers,
    };
    out.removeWhere((k, _) => k.toLowerCase() == 'user-agent');
    out['User-Agent'] = userAgent;
    return out;
  }

  static Future<R> _withOneRetry<R>(
    _Call<R> call, {
    bool recordRecoverableFailure = true,
    bool Function()? isCancelled,
  }) async {
    try {
      return await call();
    } catch (e) {
      if (isCancelled?.call() ?? false) rethrow;
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
        bool Function()? isCancelled,
        bool retryRecoverable = true,
        String? coordinatorLabel,
      }) async {
    final requestTimeout = timeout ?? defaultTimeout;
    Future<http.Response> send() async {
      await FaRequestCoordinator.instance.waitForTurn(
        label: coordinatorLabel ?? 'GET $uri',
        isCancelled: isCancelled,
      );
      if (isCancelled?.call() ?? false) {
        throw StateError('Background fetch cancelled');
      }
      final client = _ensureClient(timeout: requestTimeout);
      final response =
          await client.get(uri, headers: _mergeHeaders(headers)).timeout(requestTimeout);
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        headers: response.headers,
        responseBody: response.statusCode == 403 ? response.body : null,
      );
      return response;
    }

    if (!retryRecoverable) {
      try {
        return await send();
      } catch (error) {
        if (_isRecoverable(error)) {
          reset();
          FaRequestCoordinator.instance.recordRecoverableFailure();
        }
        rethrow;
      }
    }
    return _withOneRetry(send, isCancelled: isCancelled);
  }

  static Future<FAHttpResolvedResponse> getWithResolvedUri(
      Uri uri, {
        Map<String, String>? headers,
        Duration? timeout,
      }) async {
    final requestTimeout = timeout ?? defaultTimeout;
    return _withOneRetry(() async {
      await FaRequestCoordinator.instance.waitForTurn(
        label: 'GET $uri',
      );
      final client = _ensureClient(timeout: requestTimeout);
      return (() async {
        final request = http.Request('GET', uri)
          ..headers.addAll(_mergeHeaders(headers));
        final streamedResponse = await client.send(request);
        final resolvedUri =
            streamedResponse is http.BaseResponseWithUrl
                ? (streamedResponse as http.BaseResponseWithUrl).url
                : uri;
        final response = await http.Response.fromStream(streamedResponse);
        FaRequestCoordinator.instance.recordHttpStatus(
          statusCode: response.statusCode,
          headers: response.headers,
          responseBody:
              response.statusCode == 403 ? response.body : null,
        );
        return FAHttpResolvedResponse(
          response: response,
          resolvedUri: resolvedUri,
        );
      })()
          .timeout(requestTimeout);
    });
  }

  static Future<http.Response> getMedia(
      Uri uri, {
        Map<String, String>? headers,
        Duration? timeout,
      }) async {
    final requestTimeout = timeout ?? defaultTimeout;
    return _withOneRetry(
      () async {
        final client = _ensureClient(timeout: requestTimeout);
        return client.get(uri, headers: _mergeHeaders(headers)).timeout(requestTimeout);
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
        bool retryRecoverable = true,
      }) async {
    final requestTimeout = timeout ?? defaultTimeout;
    Future<http.Response> send() async {
      await FaRequestCoordinator.instance.waitForTurn(
        label: 'POST $uri',
      );
      final client = _ensureClient(timeout: requestTimeout);
      final response = await client
          .post(uri, headers: _mergeHeaders(headers), body: body, encoding: encoding)
          .timeout(requestTimeout);
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        headers: response.headers,
        responseBody: response.statusCode == 403 ? response.body : null,
      );
      return response;
    }

    if (!retryRecoverable) {
      try {
        return await send();
      } catch (error) {
        if (_isRecoverable(error)) {
          reset();
          FaRequestCoordinator.instance.recordRecoverableFailure();
        }
        rethrow;
      }
    }
    return _withOneRetry(send);
  }
}
