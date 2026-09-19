import 'package:fanotifier/features/submissions/domain/submission_action_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_delete_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_details_load_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_links_load_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_file_download_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_media_export_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_page_response.dart';
import 'package:fanotifier/features/submissions/domain/submission_attachment.dart';
import 'package:fanotifier/features/submissions/domain/submission_user_actions_load_result.dart';

abstract interface class SubmissionDetailsRepository {
  Future<bool> loadSfwEnabled();

  Future<bool> hasAuthCookies();

  Future<SubmissionPageResponse> fetchPage({
    required String url,
    required bool sfwEnabled,
    required bool nsfwAllowed,
    Map<String, String>? additionalHeaders,
    bool skipSfw = false,
  });

  Future<SubmissionDetailsLoadResult> loadDetails({
    required String submissionId,
    required SubmissionPageFetcher fetch,
  });

  Future<SubmissionUserActionsLoadResult> loadUserActions({
    required String author,
    required SubmissionPageFetcher fetch,
  });

  Future<SubmissionFavoriteLinksLoadResult> loadFavoriteLinks({
    required String submissionId,
    required SubmissionPageFetcher fetch,
  });

  Future<SubmissionActionResult> updateTagBlocklist({
    required String tagName,
    required bool shouldBlock,
    required String nonce,
    required String submissionId,
    required bool sfwEnabled,
  });

  Future<SubmissionActionResult> performBlockUnblock({
    required String urlPath,
    required String keyValue,
    required String linkUsername,
    required bool sfwEnabled,
  });

  Future<SubmissionActionResult> performWatchUnwatch({
    required String urlPath,
    required bool sfwEnabled,
  });

  Future<int?> sendAuthenticatedGet({
    required String url,
    required bool sfwEnabled,
  });

  Future<SubmissionDeletePrepareResult?> prepareDeletion({
    required String submissionId,
  });

  Future<bool?> confirmDeletion({
    required SubmissionDeleteConfirmationData confirmationData,
    required String password,
  });

  Future<bool> submitComment({
    required String message,
    required String submissionId,
  });

  Future<SubmissionMediaExportResult> exportToGallery(String imageUrl);

  Future<SubmissionMediaExportResult> shareFromUrl(String imageUrl);

  Future<SubmissionFileDownloadResult> downloadSubmissionFile({
    required SubmissionAttachment attachment,
    required bool sfwEnabled,
    required bool nsfwAllowed,
  });

  DateTime? parsePublicationTime(
    String rawTime, {
    required bool applyDstCorrection,
  });

  String? extractActionKey(String actionLink, String? fallbackKey);

  String replaceTruncatedSubmissionLinks(String htmlContent);

  String? findFullShortenedCommentLink(
    String commentHtml,
    String truncatedUrl,
  );

  String buildChangeInfoUrl(String submissionId);

  String buildChangeThumbnailUrl(String submissionId);

  String buildChangeSubmissionUrl(String submissionId);

  String buildSubmissionViewUrl(String submissionId);

  String get troubleTicketsUrl;
}
