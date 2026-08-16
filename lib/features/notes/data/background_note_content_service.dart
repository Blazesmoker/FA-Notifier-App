import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/features/notes/data/background_note_content_parser.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';

class BackgroundNoteContentService {
  BackgroundNoteContentService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  static const Duration _credentialTimeout = Duration(seconds: 5);
  static const Duration _requestGateTimeout = Duration(seconds: 8);
  static const Duration _connectTimeout = Duration(seconds: 6);
  static const Duration _sendTimeout = Duration(seconds: 6);
  static const Duration _receiveTimeout = Duration(seconds: 10);

  final FlutterSecureStorage _secureStorage;

  Future<String> fetchContent(
    String link, {
    CancelToken? cancelToken,
  }) async {
    final cookieA = await _secureStorage
        .read(key: 'fa_cookie_a')
        .timeout(_credentialTimeout);
    final cookieB = await _secureStorage
        .read(key: 'fa_cookie_b')
        .timeout(_credentialTimeout);
    if (cookieA == null || cookieB == null) {
      throw Exception('Not logged in');
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout: _connectTimeout,
        sendTimeout: _sendTimeout,
        receiveTimeout: _receiveTimeout,
      ),
    );
    final cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));
    await cookieJar.saveFromResponse(
      Uri.parse('https://www.furaffinity.net'),
      await FaCookieHelper.addCfClearanceCookie(
        [Cookie('a', cookieA), Cookie('b', cookieB)],
      ).timeout(_credentialTimeout),
    );
    final url = 'https://www.furaffinity.net$link';
    await FaRequestCoordinator.instance
        .waitForTurn(
          label: 'GET note content',
          isCancelled: () => cancelToken?.isCancelled ?? false,
        )
        .timeout(_requestGateTimeout);
    late final Response<dynamic> response;
    try {
      response = await dio.get<dynamic>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': FAHttp.userAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
          validateStatus: (status) =>
              status != null && status >= 200 && status < 600,
        ),
      );
    } on DioException catch (error) {
      final recoverable =
          error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError ||
              (error.type == DioExceptionType.unknown &&
                  error.error is SocketException);
      if (recoverable) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      rethrow;
    }
    FaRequestCoordinator.instance.recordHttpStatus(
      statusCode: response.statusCode,
      responseBody: response.statusCode == 403 ? response.data : null,
    );
    if (response.statusCode == 200) {
      return parseBackgroundNoteContent(response.data);
    }
    throw Exception('HTTP ${response.statusCode}');
  }
}

Future<String> fetchBackgroundNoteContent(
  String link, {
  CancelToken? cancelToken,
}) {
  return BackgroundNoteContentService().fetchContent(
    link,
    cancelToken: cancelToken,
  );
}
