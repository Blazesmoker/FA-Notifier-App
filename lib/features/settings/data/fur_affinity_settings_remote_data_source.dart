import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';

class FaSettingsHttpResponse {
  const FaSettingsHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

class FurAffinitySettingsRemoteDataSource {
  const FurAffinitySettingsRemoteDataSource({
    FlutterSecureStorage? secureStorage,
    SfwModePreference? sfwModePreference,
  })  : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _sfwModePreference = sfwModePreference ?? const SfwModePreference();

  final FlutterSecureStorage _secureStorage;
  final SfwModePreference _sfwModePreference;

  Future<FaSettingsHttpResponse> getAuthenticated(Uri uri) async {
    final response = await FAHttp.get(
      uri,
      headers: await _headers(
        referer: null,
        includeContentType: false,
        requireAuthentication: true,
      ),
    );
    return _toResponse(response);
  }

  Future<FaSettingsHttpResponse> postAuthenticated(
    Uri uri, {
    required Uri referer,
    required Map<String, String> body,
  }) async {
    final response = await FAHttp.post(
      uri,
      headers: await _headers(
        referer: referer,
        includeContentType: true,
        requireAuthentication: true,
      ),
      body: body,
      retryRecoverable: false,
    );
    return _toResponse(response);
  }

  Future<FaSettingsHttpResponse> postPasswordReset(
    Uri uri, {
    required Map<String, String> body,
  }) async {
    final response = await FAHttp.post(
      uri,
      headers: await _headers(
        referer: uri,
        includeContentType: true,
        requireAuthentication: false,
      ),
      body: body,
      retryRecoverable: false,
    );
    return _toResponse(response);
  }

  Future<Map<String, String>> _headers({
    required Uri? referer,
    required bool includeContentType,
    required bool requireAuthentication,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (requireAuthentication && (cookieA == null || cookieB == null)) {
      throw const FaSettingsRequestException('Not logged in.');
    }

    final headers = <String, String>{};
    if (cookieA != null && cookieB != null) {
      final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
      headers['Cookie'] = await FaCookieHelper.appendCfClearanceToCookieHeader(
        'a=$cookieA; b=$cookieB; sfw=${sfwEnabled ? '1' : '0'}',
      );
    }
    if (referer != null) headers['Referer'] = referer.toString();
    if (includeContentType) {
      headers['Origin'] = 'https://www.furaffinity.net';
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return headers;
  }

  FaSettingsHttpResponse _toResponse(http.Response response) {
    return FaSettingsHttpResponse(
      statusCode: response.statusCode,
      body: _decodeBody(response),
    );
  }

  String _decodeBody(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(response.bodyBytes, allowInvalid: true);
    }
  }
}
