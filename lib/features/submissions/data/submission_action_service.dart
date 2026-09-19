import 'package:fanotifier/features/submissions/data/submission_delete_response_parser.dart';
import 'package:fanotifier/features/submissions/data/submission_url_builder.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/features/submissions/domain/submission_delete_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_action_result.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SubmissionActionService {
  const SubmissionActionService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<SubmissionActionResult> performTagBlocklistRequest({
    required String tagName,
    required bool shouldBlock,
    required String nonce,
    required String submissionId,
    required bool sfwEnabled,
  }) async {
    final statusCode = await sendTagBlocklistRequest(
      tagName: tagName,
      shouldBlock: shouldBlock,
      nonce: nonce,
      submissionId: submissionId,
      sfwEnabled: sfwEnabled,
    );
    return _classifyActionStatus(statusCode, const {200});
  }

  Future<SubmissionActionResult> performBlockUnblockRequest({
    required String urlPath,
    required String keyValue,
    required String linkUsername,
    required bool sfwEnabled,
  }) async {
    final statusCode = await sendBlockUnblockRequest(
      urlPath: urlPath,
      keyValue: keyValue,
      linkUsername: linkUsername,
      sfwEnabled: sfwEnabled,
    );
    return _classifyActionStatus(statusCode, const {200, 302});
  }

  Future<SubmissionActionResult> performAuthenticatedGet({
    required String url,
    required bool sfwEnabled,
  }) async {
    final statusCode = await sendAuthenticatedGet(
      url: url,
      sfwEnabled: sfwEnabled,
    );
    return _classifyActionStatus(statusCode, const {200});
  }

  Future<int?> sendTagBlocklistRequest({
    required String tagName,
    required bool shouldBlock,
    required String nonce,
    required String submissionId,
    required bool sfwEnabled,
  }) async {
    final cookieHeader = await _buildAuthCookieHeader(sfwEnabled: sfwEnabled);
    if (cookieHeader == null) return null;

    final response = await FAHttp.post(
      Uri.parse(submissionTagBlockingUrl),
      headers: <String, String>{
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
        'Referer': buildSubmissionViewUrl(submissionId),
        'Origin': submissionFaOrigin,
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

    final fullUrl = buildSubmissionAbsolutePath(urlPath);
    final response = await FAHttp.post(
      Uri.parse(fullUrl),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
        'Referer': buildSubmissionUserUrl(linkUsername),
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

    final response = await FAHttp.get(
      Uri.parse(url),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
      },
    );

    return response.statusCode;
  }

  Future<SubmissionDeletePrepareResult?> prepareDeletion({
    required String submissionId,
  }) async {
    final cookieHeader = await _buildBasicAuthCookieHeader();
    if (cookieHeader == null) return null;

    final response = await FAHttp.post(
      Uri.parse(submissionControlsUrl),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
        'Referer': buildSubmissionViewUrl(submissionId),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'submission_ids[]': submissionId,
        'delete_submissions_submit': '1',
      },
    );

    if (response.statusCode != 200) {
      return SubmissionDeletePrepareResult(
        statusCode: response.statusCode,
        confirmationData: null,
      );
    }

    return SubmissionDeletePrepareResult(
      statusCode: response.statusCode,
      confirmationData: parseSubmissionDeleteConfirmation(response.body),
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

    final response = await FAHttp.post(
      Uri.parse(submissionControlsUrl),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          cookieHeader,
        ),
        'Referer': submissionControlsUrl,
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

    return isSubmissionDeletionConfirmed(response.body);
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

  SubmissionActionResult _classifyActionStatus(
    int? statusCode,
    Set<int> successCodes,
  ) {
    if (statusCode == null) {
      return const SubmissionActionResult(
        status: SubmissionActionStatus.missingAuth,
      );
    }
    return SubmissionActionResult(
      status: successCodes.contains(statusCode)
          ? SubmissionActionStatus.success
          : SubmissionActionStatus.failure,
      statusCode: statusCode,
    );
  }
}
