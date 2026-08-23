import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_profile_management_models.dart';

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
    final client = http.Client();
    try {
      await FaRequestCoordinator.instance.waitForTurn(label: 'POST $uri');
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll(await _headers(
          referer: referer,
          includeContentType: true,
          requireAuthentication: true,
        ))
        ..headers['User-Agent'] = FAHttp.userAgent
        ..bodyFields = body;
      final response = await http.Response.fromStream(
        await client.send(request).timeout(FAHttp.defaultTimeout),
      );
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        headers: response.headers,
        responseBody: response.statusCode == 403 ? response.body : null,
      );
      return _toResponse(response);
    } catch (error) {
      if (_isRecoverable(error)) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      rethrow;
    } finally {
      client.close();
    }
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

  Future<FaSettingsHttpResponse> sendAuthenticatedWithoutRedirect(
    Uri uri, {
    required Uri referer,
  }) async {
    final client = http.Client();
    try {
      await FaRequestCoordinator.instance.waitForTurn(label: 'GET $uri');
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll(await _headers(
          referer: referer,
          includeContentType: false,
          requireAuthentication: true,
        ))
        ..headers['User-Agent'] = FAHttp.userAgent;
      final response = await http.Response.fromStream(
        await client.send(request).timeout(FAHttp.defaultTimeout),
      );
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        headers: response.headers,
        responseBody: response.statusCode == 403 ? response.body : null,
      );
      return _toResponse(response);
    } catch (error) {
      if (_isRecoverable(error)) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<FaSettingsHttpResponse> postMultipartAuthenticated(
    Uri uri, {
    required Uri referer,
    required Map<String, String> fields,
    required String fileField,
    required FaUploadFile file,
  }) async {
    final client = http.Client();
    try {
      await FaRequestCoordinator.instance.waitForTurn(label: 'POST $uri');
      final request = http.MultipartRequest('POST', uri)
        ..followRedirects = false
        ..fields.addAll(fields)
        ..headers.addAll(await _headers(
          referer: referer,
          includeContentType: false,
          requireAuthentication: true,
        ))
        ..headers['Origin'] = 'https://www.furaffinity.net'
        ..headers['User-Agent'] = FAHttp.userAgent
        ..files.add(
          http.MultipartFile.fromBytes(
            fileField,
            file.bytes,
            filename: file.fileName,
            contentType: MediaType.parse(file.contentType),
          ),
        );
      final response = await http.Response.fromStream(
        await client.send(request).timeout(FAHttp.defaultTimeout),
      );
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        headers: response.headers,
        responseBody: response.statusCode == 403 ? response.body : null,
      );
      return _toResponse(response);
    } catch (error) {
      if (_isRecoverable(error)) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      rethrow;
    } finally {
      client.close();
    }
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

  bool _isRecoverable(Object error) {
    return error is http.ClientException ||
        error is TimeoutException ||
        error is SocketException ||
        error is HandshakeException;
  }
}
