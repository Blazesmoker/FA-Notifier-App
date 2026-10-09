import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/submissions/data/submission_cookie_service.dart';
import 'package:fanotifier/features/submissions/data/submission_html_parser.dart';
import 'package:fanotifier/features/submissions/data/submission_content_block_parser.dart';
import 'package:fanotifier/features/submissions/data/submission_url_builder.dart';
import 'package:fanotifier/shared/fa/domain/fa_content_block_data.dart';
import 'package:fanotifier/shared/fa/domain/fa_content_block_repository.dart';

class SubmissionContentBlockRepositoryImpl implements FaContentBlockRepository {
  const SubmissionContentBlockRepositoryImpl({
    this._cookieService = const SubmissionCookieService(),
    this._sfwModePreference = const SfwModePreference(),
  });

  final SubmissionCookieService _cookieService;
  final SfwModePreference _sfwModePreference;

  @override
  Future<FaContentBlockData?> fetchSubmissionTags({
    required String submissionId,
    required bool Function() isCancelled,
  }) async {
    if (!RegExp(r'^\d+$').hasMatch(submissionId) || isCancelled()) return null;
    if (!await _cookieService.hasAuthCookies() || isCancelled()) return null;
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    if (isCancelled()) return null;
    final response = await _cookieService.getWithSfwCookie(
      url: buildSubmissionViewUrl(submissionId),
      sfwEnabled: sfwEnabled,
      nsfwAllowed: false,
      isCancelled: isCancelled,
    );
    if (isCancelled() || response.statusCode != 200) return null;
    if (FaCookieHelper.isCloudflareChallengePage(
      body: response.body,
      statusCode: response.statusCode,
      headers: response.headers,
    )) {
      return null;
    }
    final document = await parseSubmissionHtmlDocument(
      decodeSubmissionResponseBody(response.bodyBytes),
    );
    if (isCancelled()) return null;
    final image = document.querySelector('img#submissionImg');
    if (image == null) return null;
    return parseSubmissionContentBlockData(document);
  }
}
