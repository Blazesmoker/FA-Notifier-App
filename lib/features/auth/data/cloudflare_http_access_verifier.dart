import 'dart:convert';
import 'dart:io';

import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/features/auth/data/fa_access_page_classifier.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_http_access_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CloudflareHttpAccessVerifier {
  const CloudflareHttpAccessVerifier({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  String get userAgent => FAHttp.userAgent;

  Future<CloudflareHttpAccessResult> verify({
    required String url,
    bool Function()? isCancelled,
  }) async {
    final initialUri = Uri.tryParse(url);
    if (initialUri == null) {
      return const CloudflareHttpAccessResult(
        status: CloudflareHttpAccessStatus.denied,
      );
    }
    var uri = initialUri;
    final visited = <Uri>{};
    try {
      for (var hop = 0; hop < 6; hop++) {
        if (isCancelled?.call() ?? false) {
          return const CloudflareHttpAccessResult(
            status: CloudflareHttpAccessStatus.cancelled,
          );
        }
        if (uri.scheme != 'https' ||
            uri.userInfo.isNotEmpty ||
            (uri.hasPort && uri.port != 443) ||
            (uri.host != 'www.furaffinity.net' &&
                uri.host != 'furaffinity.net') ||
            !visited.add(uri)) {
          break;
        }
        final cookieHeader = await FaCookieHelper.appendCfClearanceToCookieHeader(
          await _getCookieHeader(),
        );
        final resolved = await FAHttp.getWithResolvedUri(
          uri,
          followRedirects: false,
          isCancelled: isCancelled,
          coordinatorLabel: 'Cloudflare access verification',
          headers: {
            if (cookieHeader.isNotEmpty) HttpHeaders.cookieHeader: cookieHeader,
            'User-Agent': FAHttp.userAgent,
            'Referer': 'https://www.furaffinity.net/',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        );
        if (isCancelled?.call() ?? false) {
          return const CloudflareHttpAccessResult(
            status: CloudflareHttpAccessStatus.cancelled,
          );
        }
        final response = resolved.response;

        await FaCookieHelper.acceptCfClearanceHeaders(
          uri: uri,
          headers: [if (response.headers['set-cookie'] != null)
            response.headers['set-cookie']!],
        );
        if (isCancelled?.call() ?? false) {
          return const CloudflareHttpAccessResult(
            status: CloudflareHttpAccessStatus.cancelled,
          );
        }
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers['location'];
          if (location == null || location.isEmpty) break;
          uri = uri.resolve(location);
          continue;
        }
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        final access = classifyFaAccessPage(
          url: uri.toString(),
          body: body,
          statusCode: response.statusCode,
          headers: response.headers,
        );
        recordFaAccessAvailability(access);
        if (kDebugMode) {
          debugPrint(
            '[Cloudflare] HTTP verification status=${response.statusCode}, '
            'challenge=${access.status == CloudflareHttpAccessStatus.challenged}, '
            'document=${access.granted}',
          );
        }
        return access;
      }
    } catch (_) {
      if (kDebugMode) debugPrint('[Cloudflare] HTTP verification unavailable.');
      return CloudflareHttpAccessResult(
        status: (isCancelled?.call() ?? false)
            ? CloudflareHttpAccessStatus.cancelled
            : CloudflareHttpAccessStatus.unavailable,
      );
    }
    return const CloudflareHttpAccessResult(
      status: CloudflareHttpAccessStatus.denied,
    );
  }

  Future<String> _getCookieHeader() async {
    const cookieKeys = <String>[
      'a',
      'b',
      'cc',
      'folder',
      'nodesc',
      'sz',
      'sfw',
    ];

    final cookies = <String>[];
    for (final key in cookieKeys) {
      final value = await _secureStorage.read(key: 'fa_cookie_$key');
      if (value != null && value.isNotEmpty) {
        cookies.add('$key=$value');
      }
    }
    return cookies.join('; ');
  }
}
