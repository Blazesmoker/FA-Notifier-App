import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/network.dart';
import 'package:FANotifier/features/submissions/domain/openpost_delete_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;

class OpenPostActionService {
  const OpenPostActionService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<int?> sendTagBlocklistRequest({
    required String tagName,
    required bool shouldBlock,
    required String nonce,
    required String submissionId,
    required bool sfwEnabled,
  }) async {
    final cookieHeader = await _buildAuthCookieHeader(sfwEnabled: sfwEnabled);
    if (cookieHeader == null) return null;

    final response = await httpClient.post(
      Uri.parse('https://www.furaffinity.net/route/tag_blocking'),
      headers: <String, String>{
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/view/$submissionId/',
        'Origin': 'https://www.furaffinity.net',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'action': shouldBlock ? 'add-tag' : 'remove-tag',
        'key': nonce,
        'tag_name': tagName,
      },
    );

    return response.statusCode;
  }

  Future<int?> sendBlockUnblockRequest({
    required String urlPath,
    required String keyValue,
    required String linkUsername,
    required bool sfwEnabled,
  }) async {
    final cookieHeader = await _buildAuthCookieHeader(sfwEnabled: sfwEnabled);
    if (cookieHeader == null) return null;

    final fullUrl = 'https://www.furaffinity.net$urlPath';
    final response = await httpClient.post(
      Uri.parse(fullUrl),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/user/$linkUsername/',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'key': keyValue},
    );

    return response.statusCode;
  }

  Future<int?> sendAuthenticatedGet({
    required String url,
    required bool sfwEnabled,
  }) async {
    final cookieHeader = await _buildAuthCookieHeader(sfwEnabled: sfwEnabled);
    if (cookieHeader == null) return null;

    final response = await httpClient.get(
      Uri.parse(url),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
        'User-Agent': FAHttp.userAgent,
      },
    );

    return response.statusCode;
  }

  Future<OpenPostDeletePrepareResult?> prepareDeletion({
    required String submissionId,
  }) async {
    final cookieHeader = await _buildBasicAuthCookieHeader();
    if (cookieHeader == null) return null;

    final response = await httpClient.post(
      Uri.parse('https://www.furaffinity.net/controls/submissions/'),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/view/$submissionId/',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'submission_ids[]': submissionId,
        'delete_submissions_submit': '1',
      },
    );

    if (response.statusCode != 200) {
      return OpenPostDeletePrepareResult(
        statusCode: response.statusCode,
        confirmationData: null,
      );
    }

    final document = html_parser.parse(response.body);

    final confirmInput = document.querySelector('button[name="confirm"]');
    final confirmValue = confirmInput?.attributes['value'];
    final deleteSubmissionsSubmitInput =
        document.querySelector('input[name="delete_submissions_submit"]');
    final deleteSubmissionsSubmitValue =
        deleteSubmissionsSubmitInput?.attributes['value'];
    final submissionIdsInput =
        document.querySelector('input[name="submission_ids[]"]');
    final submissionIdValue = submissionIdsInput?.attributes['value'];

    final confirmationData = confirmValue == null ||
            deleteSubmissionsSubmitValue == null ||
            submissionIdValue == null
        ? null
        : OpenPostDeleteConfirmationData(
            confirmValue: confirmValue,
            deleteSubmissionsSubmitValue: deleteSubmissionsSubmitValue,
            submissionIdValue: submissionIdValue,
          );

    return OpenPostDeletePrepareResult(
      statusCode: response.statusCode,
      confirmationData: confirmationData,
    );
  }

  Future<bool?> confirmDeletion({
    required String confirmValue,
    required String deleteSubmissionsSubmitValue,
    required String submissionIdValue,
    required String password,
  }) async {
    final cookieHeader = await _buildBasicAuthCookieHeader();
    if (cookieHeader == null) return null;

    final response = await httpClient.post(
      Uri.parse('https://www.furaffinity.net/controls/submissions/'),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
        'User-Agent': FAHttp.userAgent,
        'Referer': 'https://www.furaffinity.net/controls/submissions/',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'delete_submissions_submit': deleteSubmissionsSubmitValue,
        'submission_ids[]': submissionIdValue,
        'password': password,
        'confirm': confirmValue,
      },
    );

    if (response.statusCode != 302) {
      return false;
    }

    final document = html_parser.parse(response.body);
    final bodyText = document.body?.text.trim() ?? '';
    return bodyText.isEmpty ||
        bodyText.toLowerCase().contains('there are no submissions to list');
  }

  Future<String?> _buildAuthCookieHeader({required bool sfwEnabled}) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      return null;
    }
    final sfwValue = sfwEnabled ? '1' : '0';
    return 'a=$cookieA; b=$cookieB; sfw=$sfwValue';
  }

  Future<String?> _buildBasicAuthCookieHeader() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      return null;
    }
    return 'a=$cookieA; b=$cookieB';
  }
}
