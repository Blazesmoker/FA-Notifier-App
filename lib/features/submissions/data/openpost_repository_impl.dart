import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/shared/fa/domain/submission_comment_repository.dart';
import 'package:FANotifier/features/submissions/data/openpost_action_service.dart';
import 'package:FANotifier/features/submissions/data/openpost_cookie_service.dart';
import 'package:FANotifier/features/submissions/data/openpost_details_loader.dart';
import 'package:FANotifier/features/submissions/data/openpost_favorite_links_loader.dart';
import 'package:FANotifier/features/submissions/data/openpost_html_parser.dart';
import 'package:FANotifier/features/submissions/data/openpost_link_parser.dart'
    as openpost_links;
import 'package:FANotifier/features/submissions/data/openpost_media_export_service.dart';
import 'package:FANotifier/features/submissions/data/openpost_url_builder.dart'
    as openpost_urls;
import 'package:FANotifier/features/submissions/data/openpost_user_actions_loader.dart';
import 'package:FANotifier/features/submissions/data/submission_publication_time_parser.dart';
import 'package:FANotifier/features/submissions/domain/openpost_action_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_delete_models.dart';
import 'package:FANotifier/features/submissions/domain/openpost_details_load_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_favorite_links_load_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_media_export_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_page_response.dart';
import 'package:FANotifier/features/submissions/domain/openpost_repository.dart';
import 'package:FANotifier/features/submissions/domain/openpost_user_actions_load_result.dart';

class OpenPostRepositoryImpl implements OpenPostRepository {
  OpenPostRepositoryImpl({
    OpenPostActionService actionService = const OpenPostActionService(),
    OpenPostCookieService cookieService = const OpenPostCookieService(),
    SfwModePreference sfwModePreference = const SfwModePreference(),
    OpenPostDetailsLoader detailsLoader = const OpenPostDetailsLoader(),
    OpenPostUserActionsLoader userActionsLoader =
        const OpenPostUserActionsLoader(),
    OpenPostMediaExportService mediaExportService =
        const OpenPostMediaExportService(),
    required SubmissionCommentRepository submissionCommentRepository,
  })  : _actionService = actionService,
        _cookieService = cookieService,
        _sfwModePreference = sfwModePreference,
        _detailsLoader = detailsLoader,
        _userActionsLoader = userActionsLoader,
        _mediaExportService = mediaExportService,
        _submissionCommentRepository = submissionCommentRepository;

  final OpenPostActionService _actionService;
  final OpenPostCookieService _cookieService;
  final SfwModePreference _sfwModePreference;
  final OpenPostDetailsLoader _detailsLoader;
  final OpenPostUserActionsLoader _userActionsLoader;
  final OpenPostMediaExportService _mediaExportService;
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
  Future<OpenPostPageResponse> fetchPage({
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
        isHtml ? decodeOpenPostResponseBody(response.bodyBytes) : '';

    return OpenPostPageResponse(
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
  Future<OpenPostDetailsLoadResult> loadDetails({
    required String submissionId,
    required OpenPostPageFetcher fetch,
  }) {
    return _detailsLoader.load(
      url: openpost_urls.buildSubmissionViewUrl(submissionId),
      fetch: fetch,
    );
  }

  @override
  Future<OpenPostUserActionsLoadResult> loadUserActions({
    required String author,
    required OpenPostPageFetcher fetch,
  }) {
    return _userActionsLoader.load(
      url: openpost_urls.buildOpenPostUserUrl(author),
      fetch: fetch,
    );
  }

  @override
  Future<OpenPostFavoriteLinksLoadResult> loadFavoriteLinks({
    required String submissionId,
    required OpenPostPageFetcher fetch,
  }) {
    return OpenPostFavoriteLinksLoader(cookieService: _cookieService).load(
      url: openpost_urls.buildSubmissionViewUrl(submissionId),
      fetch: fetch,
    );
  }

  @override
  Future<OpenPostActionResult> updateTagBlocklist({
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
  Future<OpenPostActionResult> performBlockUnblock({
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
  Future<OpenPostActionResult> performWatchUnwatch({
    required String urlPath,
    required bool sfwEnabled,
  }) {
    return _actionService.performAuthenticatedGet(
      url: openpost_urls.buildOpenPostAbsolutePath(urlPath),
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
  Future<OpenPostDeletePrepareResult?> prepareDeletion({
    required String submissionId,
  }) {
    return _actionService.prepareDeletion(submissionId: submissionId);
  }

  @override
  Future<bool?> confirmDeletion({
    required OpenPostDeleteConfirmationData confirmationData,
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
  Future<OpenPostMediaExportResult> exportToGallery(String imageUrl) {
    return _mediaExportService.exportToGallery(imageUrl);
  }

  @override
  Future<OpenPostMediaExportResult> shareFromUrl(String imageUrl) {
    return _mediaExportService.shareFromUrl(imageUrl);
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
    return openpost_links.extractOpenPostActionKey(actionLink, fallbackKey);
  }

  @override
  String replaceTruncatedSubmissionLinks(String htmlContent) {
    return openpost_links.replaceTruncatedSubmissionLinks(htmlContent);
  }

  @override
  String? findFullShortenedCommentLink(
    String commentHtml,
    String truncatedUrl,
  ) {
    return openpost_links.findFullShortenedCommentLink(
      commentHtml,
      truncatedUrl,
    );
  }

  @override
  String buildChangeInfoUrl(String submissionId) {
    return openpost_urls.buildOpenPostChangeInfoUrl(submissionId);
  }

  @override
  String buildChangeSubmissionUrl(String submissionId) {
    return openpost_urls.buildOpenPostChangeSubmissionUrl(submissionId);
  }

  @override
  String buildSubmissionViewUrl(String submissionId) {
    return openpost_urls.buildSubmissionViewUrl(submissionId);
  }

  @override
  String get troubleTicketsUrl => openpost_urls.openPostTroubleTicketsUrl;
}
