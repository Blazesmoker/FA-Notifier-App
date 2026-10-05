import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/features/ads/data/fa_ad_cookie_store.dart';
import 'package:fanotifier/features/ads/data/fa_ad_parser.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';

enum FaAdRequestKind { delivery, image, impression, click }

class FaAdResponse {
  const FaAdResponse(this.status, this.headers, this.bytes);

  final int status;
  final Headers headers;
  final Uint8List bytes;

  String get text => utf8.decode(bytes, allowMalformed: true);
}

class FaAdTransport {
  FaAdTransport({FaAdCookieStore? cookies})
      : _cookies = cookies ?? FaAdCookieStore(),
        _dio = Dio(BaseOptions(
          connectTimeout: FAHttp.defaultTimeout,
          receiveTimeout: FAHttp.defaultTimeout,
          sendTimeout: FAHttp.defaultTimeout,
          followRedirects: false,
          validateStatus: (_) => true,
          responseType: ResponseType.bytes,
        ));

  final FaAdCookieStore _cookies;
  final Dio _dio;
  final Set<CancelToken> _pending = {};
  int _epoch = 0;
  int _sequence = 0;
  DateTime? _previousTrackingStart;
  bool _disposed = false;

  Future<void> acceptDocumentCookies({
    required Uri documentUri,
    required String? setCookieHeader,
  }) async {
    if (_disposed || setCookieHeader == null || setCookieHeader.isEmpty ||
        documentUri.scheme != 'https' || documentUri.userInfo.isNotEmpty ||
        (documentUri.host != 'www.furaffinity.net' && documentUri.host != 'furaffinity.net')) {
      return;
    }
    final cookies = setCookieHeader.split(RegExp(r',(?=\s*[^=;,\s]+\s*=)'));
    await _cookies.storeResponse(documentUri, cookies);
    FaAdsLog.event(FaAdsLogCategory.cookie, 'document_response_bridged',
        counts: {'cookieUpdates': cookies.length});
  }

  Future<FaAdResponse> get({
    required Uri uri,
    required FaAdPageContext page,
    required FaAdRequestKind kind,
    required FaAdCancellation cancellation,
    bool Function()? canStart,
    String? referrer,
  }) async {
    final epoch = _epoch;
    final token = CancelToken();
    _pending.add(token);
    final detach = cancellation.onCancel(() => token.cancel());
    bool cancelled() => _disposed || epoch != _epoch ||
        cancellation.isCancelled || token.isCancelled;
    final gated = kind != FaAdRequestKind.image;
    final request = ++_sequence;
    final clock = Stopwatch()..start();
    try {
      if (cancelled()) throw const FaAdFailure(FaAdFailureReason.cancelled);
      final allowed = switch (kind) {
        FaAdRequestKind.delivery => isFaAdEndpoint(uri, 'spc.php'),
        FaAdRequestKind.image => isFaAdImage(uri),
        FaAdRequestKind.impression => isFaAdEndpoint(uri, 'lg.php'),
        FaAdRequestKind.click => isFaAdEndpoint(uri, 'cl.php') || isFaAdEndpoint(uri, 'ck.php'),
      };
      if (!allowed) throw const FaAdFailure(FaAdFailureReason.invalidResponse);
      FaAdsLog.event(FaAdsLogCategory.check, '${kind.name}_contract',
          counts: {'request': request},
          checks: {'allowedFaEndpoint': allowed, 'getOnly': true, 'automaticRetry': false});
      final cookies = await _cookies.prepareHeader(uri, sfwEnabled: page.sfwEnabled);
      if (gated) {
        await FaRequestCoordinator.instance.waitForTurn(
          label: '[FAAds] ${kind.name} #$request',
          isCancelled: () => cancelled() || !(canStart?.call() ?? true),
        );
      }
      if (cancelled() || !(canStart?.call() ?? true)) {
        throw const FaAdFailure(FaAdFailureReason.cancelled);
      }
      final cookieHeader = cookies.value;
      final requestReferrer = referrer ?? faAdReferrer(page.documentUri, uri);
      final now = DateTime.now();
      FaAdsLog.event(FaAdsLogCategory.http, '${kind.name}_start',
          counts: {
            'request': request,
            'queuedMs': clock.elapsedMilliseconds,
            if (gated && _previousTrackingStart != null)
              'trackingGapMs': now.difference(_previousTrackingStart!).inMilliseconds,
          },
          checks: {
            'gated': gated,
            'versionedAgent': FAHttp.userAgent == '${FAHttp.appName} v${FAHttp.appVersion}',
            'knownAppVersion': FAHttp.appVersion != '0.0.0',
            'hasReferrer': requestReferrer.isNotEmpty,
            'originReferrer': requestReferrer == 'https://www.furaffinity.net/',
            'redirectsDisabled': true,
            'automaticRetry': false,
            'modeMatchesPage': page.sfwEnabled
                ? cookieHeader.split('; ').contains('sfw=1')
                : !cookieHeader.split('; ').any((cookie) => cookie.startsWith('sfw=')),
          });
      if (gated) _previousTrackingStart = now;
      final response = await _dio.get<List<int>>(
        uri.toString(),
        cancelToken: token,
        options: Options(headers: {
          HttpHeaders.userAgentHeader: FAHttp.userAgent,
          if (cookieHeader.isNotEmpty) HttpHeaders.cookieHeader: cookieHeader,
          if (requestReferrer.isNotEmpty) HttpHeaders.refererHeader: requestReferrer,
          HttpHeaders.acceptHeader: kind == FaAdRequestKind.image ||
                  kind == FaAdRequestKind.impression
              ? 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
              : '*/*',
          if (gated) HttpHeaders.cacheControlHeader: 'no-cache',
          if (gated) 'Pragma': 'no-cache',
        }),
      );
      if (cancelled()) throw const FaAdFailure(FaAdFailureReason.cancelled);
      final status = response.statusCode ?? 0;
      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      if (gated) {
        FaRequestCoordinator.instance.recordHttpStatus(
          statusCode: status,
          headers: response.headers.map.map((key, values) => MapEntry(key, values.join(', '))),
          responseBody: status == 403 ? utf8.decode(bytes, allowMalformed: true) : null,
        );
      }
      await _cookies.storeResponse(uri, response.headers[HttpHeaders.setCookieHeader] ?? const []);
      if (cancelled()) throw const FaAdFailure(FaAdFailureReason.cancelled);
      FaAdsLog.event(FaAdsLogCategory.http, '${kind.name}_response',
          counts: {'request': request, 'status': status, 'elapsedMs': clock.elapsedMilliseconds},
          checks: {
            'redirect': status >= 300 && status < 400,
            'hasLocation': response.headers.value(HttpHeaders.locationHeader) != null,
            'requestUriPreserved': response.requestOptions.uri.toString() == uri.toString(),
            'userAgentPreserved': response.requestOptions.headers[HttpHeaders.userAgentHeader] == FAHttp.userAgent,
          });
      return FaAdResponse(status, response.headers, bytes);
    } catch (error) {
      if (error is FaAdFailure) rethrow;
      final wasCancelled = cancelled() || !(canStart?.call() ?? true);
      if (gated && !wasCancelled && error is DioException &&
          error.type != DioExceptionType.badResponse) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      FaAdsLog.event(FaAdsLogCategory.http, '${kind.name}_failed',
          counts: {'request': request}, checks: {'cancelled': wasCancelled, 'willRetry': false});
      throw FaAdFailure(wasCancelled ? FaAdFailureReason.cancelled : FaAdFailureReason.network);
    } finally {
      detach();
      _pending.remove(token);
    }
  }

  Future<void> resetSession() async {
    _epoch++;
    for (final token in _pending.toList(growable: false)) {
      token.cancel();
    }
    _previousTrackingStart = null;
    await _cookies.reset();
    FaAdsLog.event(FaAdsLogCategory.lifecycle, 'session_reset');
  }

  void dispose() {
    _disposed = true;
    resetSession();
    _dio.close(force: true);
  }
}

String faAdReferrer(Uri source, Uri target) {
  if (source.scheme == 'https' && target.scheme != 'https') return '';
  if (source.origin != target.origin) return '${source.origin}/';
  return source.replace(fragment: '', userInfo: '').toString();
}
