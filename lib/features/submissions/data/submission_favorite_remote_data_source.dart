import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';
import 'package:fanotifier/shared/fa/parsing/submission_favorite_links_parser.dart';

class SubmissionFavoriteRemoteDataSource {
  const SubmissionFavoriteRemoteDataSource({
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

  Future<SubmissionFavoriteMutationResult> setFavoriteState({
    required String submissionId,
    required bool isFavorite,
    String? favUrl,
    String? unfavUrl,
    bool? sfwEnabled,
  }) async {
    if (!RegExp(r'^\d+$').hasMatch(submissionId)) {
      return SubmissionFavoriteMutationResult(
        success: false,
        confirmedState: !isFavorite,
        changed: false,
      );
    }
    final knownUrl = isFavorite ? favUrl : unfavUrl;
    final knownAction = _validatedActionUri(
      knownUrl,
      submissionId: submissionId,
      isFavorite: isFavorite,
    );
    if (knownAction != null) {
      return _sendKnownAction(
        submissionId: submissionId,
        isFavorite: isFavorite,
        actionUri: knownAction,
        sfwEnabled: sfwEnabled,
      );
    }

    return FaRequestCoordinator.instance.runExclusive((waitForTurn) async {
      final client = http.Client();
      try {
        final viewUri = _viewUri(submissionId);
        final headers = await _headers(
          referer: null,
          sfwEnabled: sfwEnabled,
          includeContentType: false,
        );
        await waitForTurn(label: 'GET $viewUri');
        final response = await client
            .get(viewUri, headers: headers)
            .timeout(FAHttp.defaultTimeout);
        _recordResponse(response);
        if (response.statusCode != 200) {
          return SubmissionFavoriteMutationResult(
            success: false,
            confirmedState: !isFavorite,
            changed: false,
            statusCode: response.statusCode,
          );
        }

        final links = parseSubmissionFavoriteLinksFromHtml(
          response.body,
          includeClassicFallback: true,
        );
        final serverState = links.hasUnfavUrl
            ? true
            : links.hasFavUrl
                ? false
                : null;
        if (serverState == isFavorite) {
          return SubmissionFavoriteMutationResult(
            success: true,
            confirmedState: isFavorite,
            changed: false,
            statusCode: response.statusCode,
          );
        }

        final actionUri = _validatedActionUri(
          isFavorite ? links.favUrl : links.unfavUrl,
          submissionId: submissionId,
          isFavorite: isFavorite,
        );
        if (actionUri == null) {
          return SubmissionFavoriteMutationResult(
            success: false,
            confirmedState: !isFavorite,
            changed: false,
            statusCode: response.statusCode,
          );
        }

        return await _sendAction(
          client: client,
          waitForTurn: waitForTurn,
          viewUri: viewUri,
          actionUri: actionUri,
          isFavorite: isFavorite,
          sfwEnabled: sfwEnabled,
        );
      } catch (error) {
        if (_isRecoverable(error)) {
          FaRequestCoordinator.instance.recordRecoverableFailure();
        }
        return SubmissionFavoriteMutationResult(
          success: false,
          confirmedState: !isFavorite,
          changed: false,
        );
      } finally {
        client.close();
      }
    });
  }

  Future<SubmissionFavoriteMutationResult> _sendKnownAction({
    required String submissionId,
    required bool isFavorite,
    required Uri actionUri,
    required bool? sfwEnabled,
  }) async {
    final client = http.Client();
    try {
      return await _sendAction(
        client: client,
        waitForTurn: FaRequestCoordinator.instance.waitForTurn,
        viewUri: _viewUri(submissionId),
        actionUri: actionUri,
        isFavorite: isFavorite,
        sfwEnabled: sfwEnabled,
      );
    } catch (error) {
      if (_isRecoverable(error)) {
        FaRequestCoordinator.instance.recordRecoverableFailure();
      }
      return SubmissionFavoriteMutationResult(
        success: false,
        confirmedState: !isFavorite,
        changed: false,
      );
    } finally {
      client.close();
    }
  }

  Future<SubmissionFavoriteMutationResult> _sendAction({
    required http.Client client,
    required FaExclusiveRequestTurn waitForTurn,
    required Uri viewUri,
    required Uri actionUri,
    required bool isFavorite,
    required bool? sfwEnabled,
  }) async {
    await waitForTurn(label: 'POST $actionUri');
    final request = http.Request('POST', actionUri)
      ..followRedirects = false
      ..headers.addAll(
        await _headers(
          referer: viewUri,
          sfwEnabled: sfwEnabled,
          includeContentType: true,
        ),
      );
    final response = await http.Response.fromStream(
      await client.send(request).timeout(FAHttp.defaultTimeout),
    );
    _recordResponse(response);
    final accepted = response.statusCode == 302;
    return SubmissionFavoriteMutationResult(
      success: accepted,
      confirmedState: accepted ? isFavorite : !isFavorite,
      changed: accepted,
      statusCode: response.statusCode,
    );
  }

  Future<Map<String, String>> _headers({
    required Uri? referer,
    required bool? sfwEnabled,
    required bool includeContentType,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null ||
        cookieA.isEmpty ||
        cookieB == null ||
        cookieB.isEmpty) {
      throw StateError('Not logged in.');
    }
    final effectiveSfw =
        sfwEnabled ?? await _sfwModePreference.loadSfwEnabled();
    final cookie = await FaCookieHelper.appendCfClearanceToCookieHeader(
      'a=$cookieA; b=$cookieB; sfw=${effectiveSfw ? '1' : '0'}',
    );
    final headers = <String, String>{
      'Cookie': cookie,
      'User-Agent': FAHttp.userAgent,
    };
    if (referer != null) headers['Referer'] = referer.toString();
    if (includeContentType) {
      headers['Origin'] = 'https://www.furaffinity.net';
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return headers;
  }

  Uri _viewUri(String submissionId) {
    return Uri.https('www.furaffinity.net', '/view/$submissionId/');
  }

  Uri? _validatedActionUri(
    String? value, {
    required String submissionId,
    required bool isFavorite,
  }) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final absolute = uri.hasScheme
        ? uri
        : Uri.parse('https://www.furaffinity.net').resolveUri(uri);
    if (absolute.scheme != 'https' ||
        absolute.host.toLowerCase() != 'www.furaffinity.net') {
      return null;
    }
    final segments = absolute.pathSegments
        .where((part) => part.isNotEmpty)
        .toList();
    if (segments.length < 2 ||
        segments.first != (isFavorite ? 'fav' : 'unfav') ||
        segments[1] != submissionId) {
      return null;
    }
    return absolute;
  }

  void _recordResponse(http.Response response) {
    FaRequestCoordinator.instance.recordHttpStatus(
      statusCode: response.statusCode,
      headers: response.headers,
      responseBody: response.statusCode == 403 ? response.body : null,
    );
  }

  bool _isRecoverable(Object error) {
    return error is http.ClientException ||
        error is TimeoutException ||
        error is SocketException ||
        error is HandshakeException;
  }
}
