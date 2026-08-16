import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/core/utils/utils.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';

enum BackgroundNoteUnreadOutcome {
  confirmed,
  unauthenticated,
  invalidNote,
  credentialTimeout,
  requestGateTimeout,
  requestTimeout,
  networkFailure,
  cloudflareChallenge,
  httpRejected,
}

class BackgroundNoteUnreadResult {
  const BackgroundNoteUnreadResult({
    required this.success,
    required this.outcome,
    required this.duration,
    required this.shouldRetryImmediately,
    this.statusCode,
  });

  final bool success;
  final BackgroundNoteUnreadOutcome outcome;
  final Duration duration;
  final bool shouldRetryImmediately;
  final int? statusCode;
}

class BackgroundNoteUnreadService {
  BackgroundNoteUnreadService({
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

  Future<BackgroundNoteUnreadResult> markAsUnread({
    required String noteId,
    required String link,
    CancelToken? cancelToken,
  }) {
    final cleanedNoteId = noteId.trim();
    var pageNumber = extractPageNumber(link);
    var messageId = extractMessageId(link);
    if (messageId.isEmpty && RegExp(r'^\d+$').hasMatch(cleanedNoteId)) {
      messageId = cleanedNoteId;
      pageNumber = 1;
    }
    final url = messageId.isEmpty
        ? 'https://www.furaffinity.net/msg/pms/'
        : 'https://www.furaffinity.net/msg/pms/$pageNumber/$messageId/';
    return _submitUnread(
      noteIds: <String>[messageId],
      url: url,
      requestLabel: 'POST note unread',
      cancelToken: cancelToken,
    );
  }

  Future<BackgroundNoteUnreadResult> markManyAsUnread({
    required Iterable<String> noteIds,
    CancelToken? cancelToken,
  }) {
    return _submitUnread(
      noteIds: noteIds,
      url: 'https://www.furaffinity.net/msg/pms/',
      requestLabel: 'POST notes unread',
      cancelToken: cancelToken,
    );
  }

  Future<BackgroundNoteUnreadResult> _submitUnread({
    required Iterable<String> noteIds,
    required String url,
    required String requestLabel,
    CancelToken? cancelToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    var stage = 'credentials';
    try {
      final cleanedNoteIds = noteIds
          .map((noteId) => noteId.trim())
          .where((noteId) => noteId.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (cleanedNoteIds.isEmpty ||
          cleanedNoteIds.any((noteId) => !RegExp(r'^\d+$').hasMatch(noteId))) {
        return _result(
          stopwatch,
          outcome: BackgroundNoteUnreadOutcome.invalidNote,
        );
      }

      final cookies = await Future.wait<String?>(<Future<String?>>[
        _secureStorage.read(key: 'fa_cookie_a'),
        _secureStorage.read(key: 'fa_cookie_b'),
      ]).timeout(_credentialTimeout);
      final cookieA = cookies[0];
      final cookieB = cookies[1];
      if (cookieA == null || cookieB == null) {
        return _result(
          stopwatch,
          outcome: BackgroundNoteUnreadOutcome.unauthenticated,
        );
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
          <Cookie>[Cookie('a', cookieA), Cookie('b', cookieB)],
        ).timeout(_credentialTimeout),
      );

      final formData = <String, dynamic>{
        'manage_notes': '1',
        'items[]': cleanedNoteIds,
        'move_to': 'unread',
      };
      stage = 'requestGate';
      await FaRequestCoordinator.instance
          .waitForTurn(
            label: requestLabel,
            isCancelled: () => cancelToken?.isCancelled ?? false,
          )
          .timeout(_requestGateTimeout);
      stage = 'request';
      final response = await dio.post<dynamic>(
        url,
        data: formData,
        cancelToken: cancelToken,
        options: Options(
          headers: <String, String>{
            'User-Agent': FAHttp.userAgent,
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': url,
            'Origin': 'https://www.furaffinity.net',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
            HttpHeaders.connectionHeader: 'close',
            'Cache-Control': 'max-age=0',
            'DNT': '1',
            'Upgrade-Insecure-Requests': '1',
          },
          followRedirects: false,
          listFormat: ListFormat.multi,
          validateStatus: (status) =>
              status != null && status >= 100 && status < 600,
        ),
      );
      final statusCode = response.statusCode;
      final retryAfter = response.headers.value('retry-after');
      final responseText = response.data?.toString() ?? '';
      final cloudflareChallenge = FaCookieHelper.isCloudflareChallengePage(
        body: responseText,
        statusCode: statusCode,
      );
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: statusCode,
        headers: retryAfter == null
            ? null
            : <String, String>{'retry-after': retryAfter},
        responseBody: statusCode == 403 ? response.data : null,
      );

      final confirmed =
          (statusCode == 200 || statusCode == 302) && !cloudflareChallenge;
      if (confirmed) {
        return _result(
          stopwatch,
          success: true,
          outcome: BackgroundNoteUnreadOutcome.confirmed,
          statusCode: statusCode,
        );
      }
      if (cloudflareChallenge) {
        return _result(
          stopwatch,
          outcome: BackgroundNoteUnreadOutcome.cloudflareChallenge,
          statusCode: statusCode,
        );
      }

      final retryImmediately = statusCode == 408 ||
          statusCode == 425 ||
          (statusCode != null && statusCode >= 500);
      if (retryImmediately && statusCode != 503) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      return _result(
        stopwatch,
        outcome: BackgroundNoteUnreadOutcome.httpRejected,
        statusCode: statusCode,
        shouldRetryImmediately: retryImmediately,
      );
    } on TimeoutException {
      if (stage == 'request') {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      return _result(
        stopwatch,
        outcome: switch (stage) {
          'credentials' => BackgroundNoteUnreadOutcome.credentialTimeout,
          'requestGate' => BackgroundNoteUnreadOutcome.requestGateTimeout,
          _ => BackgroundNoteUnreadOutcome.requestTimeout,
        },
        shouldRetryImmediately: stage == 'request',
      );
    } on DioException catch (error) {
      final requestTimedOut =
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout;
      final connectionFailed = error.type == DioExceptionType.connectionError ||
          (error.type == DioExceptionType.unknown &&
              error.error is SocketException);
      final retryImmediately = requestTimedOut || connectionFailed;
      if (retryImmediately) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      return _result(
        stopwatch,
        outcome: requestTimedOut
            ? BackgroundNoteUnreadOutcome.requestTimeout
            : BackgroundNoteUnreadOutcome.networkFailure,
        shouldRetryImmediately: retryImmediately,
      );
    } catch (_) {
      return _result(
        stopwatch,
        outcome: BackgroundNoteUnreadOutcome.networkFailure,
      );
    }
  }

  BackgroundNoteUnreadResult _result(
    Stopwatch stopwatch, {
    required BackgroundNoteUnreadOutcome outcome,
    bool success = false,
    bool shouldRetryImmediately = false,
    int? statusCode,
  }) {
    stopwatch.stop();
    return BackgroundNoteUnreadResult(
      success: success,
      outcome: outcome,
      duration: stopwatch.elapsed,
      shouldRetryImmediately: shouldRetryImmediately,
      statusCode: statusCode,
    );
  }
}

Future<BackgroundNoteUnreadResult> restoreBackgroundNoteAsUnread({
  required String noteId,
  required String link,
  CancelToken? cancelToken,
}) {
  return BackgroundNoteUnreadService().markAsUnread(
    noteId: noteId,
    link: link,
    cancelToken: cancelToken,
  );
}

Future<BackgroundNoteUnreadResult> restoreBackgroundNotesAsUnread({
  required Iterable<String> noteIds,
  CancelToken? cancelToken,
}) {
  return BackgroundNoteUnreadService().markManyAsUnread(
    noteIds: noteIds,
    cancelToken: cancelToken,
  );
}

Future<void> markBackgroundNoteAsUnread(
  Message message,
) async {
  final result = await restoreBackgroundNoteAsUnread(
    noteId: message.id,
    link: message.link,
  );
  if (!result.success) {
    throw StateError('Failed to restore note unread state');
  }
}
