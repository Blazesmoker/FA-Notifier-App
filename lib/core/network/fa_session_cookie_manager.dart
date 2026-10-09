import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_page_counter_observer.dart';

class FaSessionCookieManager extends CookieManager {
  FaSessionCookieManager(super.cookieJar);

  bool _isFaRequest(RequestOptions options) {
    final host = options.uri.host.toLowerCase();
    return options.uri.scheme == 'https' &&
        (host == 'furaffinity.net' || host.endsWith('.furaffinity.net'));
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isFaRequest(options)) {
      options.headers[HttpHeaders.userAgentHeader] = FAHttp.userAgent;
      if (options.extra['observeFaCounters'] != false &&
          !(options.method != 'GET' && options.uri.path.startsWith('/msg/pms'))) {
        options.extra['faPageCounterRequest'] =
            FaPageCounterObserver.instance.capture(options.uri);
      }
    }
    await super.onRequest(options, handler);
  }

  @override
  Future<String> loadCookies(RequestOptions options) async {
    final suppliedCookies = <String, String>{};
    for (final entry in options.headers.entries) {
      if (entry.key.toLowerCase() != HttpHeaders.cookieHeader) continue;
      for (final pair in entry.value.toString().split(';')) {
        final separator = pair.indexOf('=');
        if (separator <= 0) continue;
        final name = pair.substring(0, separator).trim();
        suppliedCookies.putIfAbsent(
          name,
          () => pair.substring(separator + 1).trim(),
        );
      }
    }
    final cookies = await super.loadCookies(options);
    if (!_isFaRequest(options)) return cookies;
    final replacements = Map<String, String>.from(suppliedCookies)
      ..remove('cf_clearance');
    final merged = <String>[];
    for (final pair in cookies.split(';')) {
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      if (!suppliedCookies.containsKey(name)) {
        merged.add(pair.trim());
      } else if (replacements.containsKey(name)) {
        merged.add('$name=${replacements.remove(name)}');
      }
    }
    return FaCookieHelper.appendCfClearanceToCookieHeader(
      merged.join('; '),
      uri: options.uri,
    );
  }

  @override
  Future<void> saveCookies(Response response) async {
    await super.saveCookies(response);
    if (!_isFaRequest(response.requestOptions)) return;
    await FaCookieHelper.acceptCfClearanceHeaders(
      uri: response.realUri,
      headers: response.headers[HttpHeaders.setCookieHeader] ?? const <String>[],
    );
    final body = response.data;
    final request = response.requestOptions.extra['faPageCounterRequest'];
    if (body is String && request is FaPageCounterRequest) {
      FaPageCounterObserver.instance.accept(
        request: request, uri: response.realUri,
        statusCode: response.statusCode ?? 0, html: body,
      );
    }
  }
}
