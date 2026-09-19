import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/shared/fa/domain/submission_comment_repository.dart';
import 'package:fanotifier/features/submissions/data/submission_action_service.dart';
import 'package:fanotifier/features/submissions/data/submission_cookie_service.dart';
import 'package:fanotifier/features/submissions/data/submission_details_loader.dart';
import 'package:fanotifier/features/submissions/data/submission_favorite_links_loader.dart';
import 'package:fanotifier/features/submissions/data/submission_file_download_service.dart';
import 'package:fanotifier/features/submissions/data/submission_html_parser.dart';
import 'package:fanotifier/features/submissions/data/submission_link_parser.dart'
    as submission_links;
import 'package:fanotifier/features/submissions/data/submission_media_export_service.dart';
import 'package:fanotifier/features/submissions/data/submission_url_builder.dart'
    as submission_urls;
import 'package:fanotifier/features/submissions/data/submission_user_actions_loader.dart';
import 'package:fanotifier/features/submissions/data/submission_publication_time_parser.dart';
import 'package:fanotifier/features/submissions/domain/submission_action_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_delete_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_details_load_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_links_load_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_file_download_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_media_export_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_page_response.dart';
import 'package:fanotifier/features/submissions/domain/submission_details_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_attachment.dart';
import 'package:fanotifier/features/submissions/domain/submission_user_actions_load_result.dart';

class SubmissionDetailsRepositoryImpl implements SubmissionDetailsRepository {
  SubmissionDetailsRepositoryImpl({
    this._actionService = const SubmissionActionService(),
    this._cookieService = const SubmissionCookieService(),
    this._sfwModePreference = const SfwModePreference(),
    this._detailsLoader = const SubmissionDetailsLoader(),
    this._userActionsLoader = const SubmissionUserActionsLoader(),
    this._mediaExportService = const SubmissionMediaExportService(),
    SubmissionFileDownloadService? fileDownloadService,
    required this._submissionCommentRepository,
  }) :
        _fileDownloadService = fileDownloadService ??
            SubmissionFileDownloadService(cookieService: _cookieService);

  final SubmissionActionService _actionService;
  final SubmissionCookieService _cookieService;
  final SfwModePreference _sfwModePreference;
  final SubmissionDetailsLoader _detailsLoader;
  final SubmissionUserActionsLoader _userActionsLoader;
  final SubmissionMediaExportService _mediaExportService;
  final SubmissionFileDownloadService _fileDownloadService;
  final SubmissionCommentRepository _submissionCommentRepository;

  @override
  Future<bool> loadSfwEnabled() {
    return _sfwModePreference.loadSfwEnabled();
  }

  @override
  Future<bool> hasAuthCookies() {
    return _cookieService.hasAuthCookies();
  }

  @override
  Future<SubmissionPageResponse> fetchPage({
    required String url,
    required bool sfwEnabled,
    required bool nsfwAllowed,
    Map<String, String>? additionalHeaders,
    bool skipSfw = false,
  }) async {
    final response = await _cookieService.getWithSfwCookie(
      url: url,
      sfwEnabled: sfwEnabled,
      nsfwAllowed: nsfwAllowed,
      additionalHeaders: additionalHeaders,
      skipSfw: skipSfw,
    );

    final contentType =
        (response.headers['content-type'] ?? '').toLowerCase();
    final isHtml = response.statusCode == 200 &&
        (contentType.contains('text/html') ||
            contentType.contains('application/xhtml'));
    final decodedBody =
        isHtml ? decodeSubmissionResponseBody(response.bodyBytes) : '';

    return SubmissionPageResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.body,
      bodyBytes: response.bodyBytes,
      isHtml: isHtml,
      submissionNotFound:
          isHtml && hasSubmissionNotFoundError(decodedBody),
      matureContentWarning:
          isHtml && hasMatureContentWarning(decodedBody),
      oldMatureImageError:
          isHtml && hasOldMatureImageError(decodedBody),
    );
  }

  @override
  Future<SubmissionDetailsLoadResult> loadDetails({
    required String submissionId,
    required SubmissionPageFetcher fetch,
  }) {
    return _detailsLoader.load(
      url: submission_urls.buildSubmissionViewUrl(submissionId),
      fetch: fetch,
    );
  }

  @override
  Future<SubmissionUserActionsLoadResult> loadUserActions({
    required String author,
    required SubmissionPageFetcher fetch,
  }) {
    return _userActionsLoader.load(
      url: submission_urls.buildSubmissionUserUrl(author),
      fetch: fetch,
    );
  }

  @override
  Future<SubmissionFavoriteLinksLoadResult> loadFavoriteLinks({
    required String submissionId,
    required SubmissionPageFetcher fetch,
  }) {
    return SubmissionFavoriteLinksLoader(cookieService: _cookieService).load(
      url: submission_urls.buildSubmissionViewUrl(submissionId),
      fetch: fetch,
    );
  }

  @override
  Future<SubmissionActionResult> updateTagBlocklist({
    required String tagName,
    required bool shouldBlock,
    required String nonce,
    required String submissionId,
    required bool sfwEnabled,
  }) {
    return _actionService.performTagBlocklistRequest(
      tagName: tagName,
      shouldBlock: shouldBlock,
      nonce: nonce,
      submissionId: submissionId,
      sfwEnabled: sfwEnabled,
    );
  }

  @override
  Future<SubmissionActionResult> performBlockUnblock({
    required String urlPath,
    required String keyValue,
    required String linkUsername,
    required bool sfwEnabled,
  }) {
    return _actionService.performBlockUnblockRequest(
      urlPath: urlPath,
      keyValue: keyValue,
      linkUsername: linkUsername,
      sfwEnabled: sfwEnabled,
    );
  }

  @override
  Future<SubmissionActionResult> performWatchUnwatch({
    required String urlPath,
    required bool sfwEnabled,
  }) {
    return _actionService.performAuthenticatedGet(
      url: submission_urls.buildSubmissionAbsolutePath(urlPath),
      sfwEnabled: sfwEnabled,
    );
  }

  @override
  Future<int?> sendAuthenticatedGet({
    required String url,
    required bool sfwEnabled,
  }) {
    return _actionService.sendAuthenticatedGet(
      url: url,
      sfwEnabled: sfwEnabled,
    );
  }

  @override
  Future<SubmissionDeletePrepareResult?> prepareDeletion({
    required String submissionId,
  }) {
    return _actionService.prepareDeletion(submissionId: submissionId);
  }

  @override
  Future<bool?> confirmDeletion({
    required SubmissionDeleteConfirmationData confirmationData,
    required String password,
  }) {
    return _actionService.confirmDeletion(
      confirmValue: confirmationData.confirmValue,
      deleteSubmissionsSubmitValue:
          confirmationData.deleteSubmissionsSubmitValue,
      submissionIdValue: confirmationData.submissionIdValue,
      password: password,
    );
  }

  @override
  Future<bool> submitComment({
    required String message,
    required String submissionId,
  }) {
    return _submissionCommentRepository.submitComment(
      message: message,
      submissionId: submissionId,
    );
  }

  @override
  Future<SubmissionMediaExportResult> exportToGallery(String imageUrl) {
    return _mediaExportService.exportToGallery(imageUrl);
  }

  @override
  Future<SubmissionMediaExportResult> shareFromUrl(String imageUrl) {
    return _mediaExportService.shareFromUrl(imageUrl);
  }

  @override
  Future<SubmissionFileDownloadResult> downloadSubmissionFile({
    required SubmissionAttachment attachment,
    required bool sfwEnabled,
    required bool nsfwAllowed,
  }) {
    return _fileDownloadService.download(
      attachment: attachment,
      sfwEnabled: sfwEnabled,
      nsfwAllowed: nsfwAllowed,
    );
  }

  @override
  DateTime? parsePublicationTime(
    String rawTime, {
    required bool applyDstCorrection,
  }) {
    return parseSubmissionPublicationTime(
      rawTime,
      applyDstCorrection: applyDstCorrection,
    );
  }

  @override
  String? extractActionKey(String actionLink, String? fallbackKey) {
    return submission_links.extractSubmissionActionKey(actionLink, fallbackKey);
  }

  @override
  String replaceTruncatedSubmissionLinks(String htmlContent) {
    return submission_links.replaceTruncatedSubmissionLinks(htmlContent);
  }

  @override
  String? findFullShortenedCommentLink(
    String commentHtml,
    String truncatedUrl,
  ) {
    return submission_links.findFullShortenedCommentLink(
      commentHtml,
      truncatedUrl,
    );
  }

  @override
  String buildChangeInfoUrl(String submissionId) {
    return submission_urls.buildSubmissionChangeInfoUrl(submissionId);
  }

  @override
  String buildChangeThumbnailUrl(String submissionId) {
    return submission_urls.buildSubmissionChangeThumbnailUrl(submissionId);
  }

  @override
  String buildChangeSubmissionUrl(String submissionId) {
    return submission_urls.buildSubmissionChangeSubmissionUrl(submissionId);
  }

  @override
  String buildSubmissionViewUrl(String submissionId) {
    return submission_urls.buildSubmissionViewUrl(submissionId);
  }

  @override
  String get troubleTicketsUrl => submission_urls.submissionTroubleTicketsUrl;
}
