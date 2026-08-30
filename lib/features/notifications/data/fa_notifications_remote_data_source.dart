import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/features/notifications/data/notification_removal_request_builder.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';

class FaNotificationsFetchResponse {
  const FaNotificationsFetchResponse({required this.htmlBody});

  final String htmlBody;
}

class FaNotificationMutationResponse {
  const FaNotificationMutationResponse({
    required this.statusCode,
    this.redirectLocation,
  });

  final int? statusCode;
  final String? redirectLocation;
}

class FaNotificationsRemoteSession {
  const FaNotificationsRemoteSession._({
    required this._cookieA,
    required this._cookieB,
  });

  final String _cookieA;
  final String _cookieB;
}

class FaNotificationsRemoteDataSource {
  FaNotificationsRemoteDataSource() {
    _initializeDio();
  }

  final Dio _dio = Dio();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  Future<void> _initializeDio() async {
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.headers['Accept'] =
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';
    _dio.options.headers['Accept-Encoding'] = 'gzip, deflate, br, zstd';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9,ru;q=0.8';
    _dio.options.followRedirects = false;
    _dio.options.connectTimeout = FAHttp.defaultTimeout;
    _dio.options.sendTimeout = FAHttp.defaultTimeout;
    _dio.options.receiveTimeout = FAHttp.defaultTimeout;
    _dio.options.validateStatus =
        (status) => status != null && status >= 200 && status < 600;
  }

  Future<FaNotificationsRemoteSession> createAuthenticatedSession() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('Authentication cookies not found.');
    }
    return FaNotificationsRemoteSession._(
      cookieA: cookieA,
      cookieB: cookieB,
    );
  }

  Future<FaNotificationsFetchResponse> fetchNotificationsPage(
    FaNotificationsRemoteSession session,
  ) async {
    const url = 'https://www.furaffinity.net/msg/others/';
    await FaRequestCoordinator.instance.waitForTurn(label: 'GET $url');
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Cookie': await _cookieHeader(session),
            'Referer': 'https://www.furaffinity.net/msg/others/',
          },
        ),
      );
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        headers: response.headers.map.map(
          (key, values) => MapEntry(key, values.join(',')),
        ),
        responseBody: response.statusCode == 403 ? response.data : null,
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to load notifications.');
      }
      return FaNotificationsFetchResponse(
        htmlBody: response.data.toString(),
      );
    } on DioException catch (error) {
      if (_isRecoverableDioFailure(error)) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      rethrow;
    }
  }

  Future<FaNotificationMutationResponse> removeSelected(
    FaNotificationsRemoteSession session, {
    required String formAction,
    required Map<String, dynamic> fields,
  }) {
    return _post(
      session,
      formAction: formAction,
      fields: fields,
      contentType: 'application/x-www-form-urlencoded',
      encodeUrlEncodedBody: true,
    );
  }

  Future<FaNotificationMutationResponse> nukeSection(
    FaNotificationsRemoteSession session, {
    required String formAction,
    required Map<String, dynamic> fields,
  }) {
    return _post(
      session,
      formAction: formAction,
      fields: fields,
      contentType: 'multipart/form-data',
    );
  }

  Future<FaNotificationMutationResponse> removeAllFromSection(
    FaNotificationsRemoteSession session, {
    required String formAction,
    required Map<String, dynamic> fields,
  }) {
    return _post(
      session,
      formAction: formAction,
      fields: fields,
      contentType: 'application/x-www-form-urlencoded',
    );
  }

  Future<FaNotificationMutationResponse> _post(
    FaNotificationsRemoteSession session, {
    required String formAction,
    required Map<String, dynamic> fields,
    required String contentType,
    bool encodeUrlEncodedBody = false,
  }) async {
    final data = encodeUrlEncodedBody
        ? buildNotificationUrlEncodedBody(fields)
        : buildNotificationFormData(fields);
    final url = 'https://www.furaffinity.net$formAction';
    await FaRequestCoordinator.instance.waitForTurn(label: 'POST $url');
    try {
      final response = await _dio.post(
        url,
        data: data,
        options: Options(
          headers: {
            'Referer': 'https://www.furaffinity.net/msg/others/',
            'Content-Type': contentType,
            'Cookie': await _cookieHeader(session),
          },
        ),
      );
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        headers: response.headers.map.map(
          (key, values) => MapEntry(key, values.join(',')),
        ),
        responseBody: response.statusCode == 403 ? response.data : null,
      );
      return FaNotificationMutationResponse(
        statusCode: response.statusCode,
        redirectLocation: _dioHeaderValue(response.headers, 'location'),
      );
    } on DioException catch (error) {
      if (_isRecoverableDioFailure(error)) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      rethrow;
    }
  }

  Future<String> _cookieHeader(FaNotificationsRemoteSession session) {
    return FaCookieHelper.appendCfClearanceToCookieHeader(
      'a=${session._cookieA}; b=${session._cookieB}',
    );
  }
}

bool _isRecoverableDioFailure(DioException error) {
  return error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.connectionError ||
      (error.type == DioExceptionType.unknown && error.error is SocketException);
}

String? _dioHeaderValue(Headers headers, String name) {
  final lowerName = name.toLowerCase();
  for (final entry in headers.map.entries) {
    if (entry.key.toLowerCase() == lowerName && entry.value.isNotEmpty) {
      return entry.value.first;
    }
  }
  return null;
}
