import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';

class FaManagementHttpResponse {
  const FaManagementHttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

class FaManagementPostRequest {
  FaManagementPostRequest({
    required this.uri,
    required this.referer,
    required Iterable<FaManagementFormValue> fields,
  }) : fields = List<FaManagementFormValue>.unmodifiable(fields);

  final Uri uri;
  final Uri referer;
  final List<FaManagementFormValue> fields;
}

class FaManagementGetPostResponse {
  const FaManagementGetPostResponse({
    required this.getResponse,
    required this.postResponse,
  });

  final FaManagementHttpResponse getResponse;
  final FaManagementHttpResponse postResponse;
}

class FaManagementGetPostException implements Exception {
  const FaManagementGetPostException({
    required this.cause,
    required this.postAttempted,
  });

  final Object cause;
  final bool postAttempted;

  @override
  String toString() => '$cause';
}

class SubmissionManagementRemoteDataSource {
  const SubmissionManagementRemoteDataSource({
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

  Future<FaManagementHttpResponse> getAuthenticated(Uri uri) async {
    final response = await FAHttp.get(
      uri,
      headers: await _headers(referer: null, includeContentType: false),
    );
    return _toResponse(response);
  }

  Future<FaManagementHttpResponse> postAuthenticated(
    Uri uri, {
    required Uri referer,
    required Iterable<FaManagementFormValue> fields,
  }) async {
    final client = http.Client();
    try {
      await FaRequestCoordinator.instance.waitForTurn(label: 'POST $uri');
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll(
          await _headers(referer: referer, includeContentType: true),
        )
        ..headers['User-Agent'] = FAHttp.userAgent
        ..body = _encodeFields(fields);
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
      if (isRecoverable(error)) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<FaManagementGetPostResponse> getThenPostAuthenticated(
    Uri getUri, {
    required FaManagementPostRequest Function(
      FaManagementHttpResponse response,
    ) buildPostRequest,
  }) {
    return FaRequestCoordinator.instance.runExclusive((waitForTurn) async {
      final client = http.Client();
      var postAttempted = false;
      try {
        await waitForTurn(label: 'GET $getUri');
        final getHeaders = await _headers(
          referer: null,
          includeContentType: false,
        );
        getHeaders['User-Agent'] = FAHttp.userAgent;
        final getResponse = await client
            .get(
              getUri,
              headers: getHeaders,
            )
            .timeout(FAHttp.defaultTimeout);
        FaRequestCoordinator.instance.recordHttpStatus(
          statusCode: getResponse.statusCode,
          headers: getResponse.headers,
          responseBody: getResponse.statusCode == 403 ? getResponse.body : null,
        );
        final parsedGetResponse = _toResponse(getResponse);
        final postRequest = buildPostRequest(parsedGetResponse);

        await waitForTurn(label: 'POST ${postRequest.uri}');
        final request = http.Request('POST', postRequest.uri)
          ..followRedirects = false
          ..headers.addAll(
            await _headers(
              referer: postRequest.referer,
              includeContentType: true,
            ),
          )
          ..headers['User-Agent'] = FAHttp.userAgent
          ..body = _encodeFields(postRequest.fields);
        postAttempted = true;
        final postResponse = await http.Response.fromStream(
          await client.send(request).timeout(FAHttp.defaultTimeout),
        );
        FaRequestCoordinator.instance.recordHttpStatus(
          statusCode: postResponse.statusCode,
          headers: postResponse.headers,
          responseBody:
              postResponse.statusCode == 403 ? postResponse.body : null,
        );
        return FaManagementGetPostResponse(
          getResponse: parsedGetResponse,
          postResponse: _toResponse(postResponse),
        );
      } catch (error) {
        if (isRecoverable(error)) {
          FaRequestCoordinator.instance.recordRecoverableFailure();
        }
        throw FaManagementGetPostException(
          cause: error,
          postAttempted: postAttempted,
        );
      } finally {
        client.close();
      }
    });
  }

  bool isRecoverable(Object error) {
    final cause = error is FaManagementGetPostException ? error.cause : error;
    return cause is http.ClientException ||
        cause is TimeoutException ||
        cause is SocketException ||
        cause is HandshakeException;
  }

  Future<Map<String, String>> _headers({
    required Uri? referer,
    required bool includeContentType,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null ||
        cookieA.isEmpty ||
        cookieB == null ||
        cookieB.isEmpty) {
      throw const SubmissionManagementRequestException('Not logged in.');
    }
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    final cookie = await FaCookieHelper.appendCfClearanceToCookieHeader(
      'a=$cookieA; b=$cookieB; sfw=${sfwEnabled ? '1' : '0'}',
    );
    final headers = <String, String>{'Cookie': cookie};
    if (referer != null) headers['Referer'] = referer.toString();
    if (includeContentType) {
      headers['Origin'] = 'https://www.furaffinity.net';
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return headers;
  }

  String _encodeFields(Iterable<FaManagementFormValue> fields) {
    return fields.map((field) {
      return '${Uri.encodeQueryComponent(field.name)}='
          '${Uri.encodeQueryComponent(field.value)}';
    }).join('&');
  }

  FaManagementHttpResponse _toResponse(http.Response response) {
    return FaManagementHttpResponse(
      statusCode: response.statusCode,
      body: _decode(response),
      headers: Map<String, String>.unmodifiable(response.headers),
    );
  }

  String _decode(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(response.bodyBytes, allowInvalid: true);
    }
  }
}
