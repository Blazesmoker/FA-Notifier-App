import 'package:FANotifier/features/submissions/domain/openpost_action_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_delete_models.dart';
import 'package:FANotifier/features/submissions/domain/openpost_details_load_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_favorite_links_load_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_media_export_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_page_response.dart';
import 'package:FANotifier/features/submissions/domain/openpost_user_actions_load_result.dart';

abstract interface class OpenPostRepository {
  Future<bool> loadSfwEnabled();

  Future<bool> hasAuthCookies();

  Future<OpenPostPageResponse> fetchPage({
    required String url,
    required bool sfwEnabled,
    required bool nsfwAllowed,
    Map<String, String>? additionalHeaders,
    bool skipSfw = false,
  });

  Future<OpenPostDetailsLoadResult> loadDetails({
    required String submissionId,
    required OpenPostPageFetcher fetch,
  });

  Future<OpenPostUserActionsLoadResult> loadUserActions({
    required String author,
    required OpenPostPageFetcher fetch,
  });

  Future<OpenPostFavoriteLinksLoadResult> loadFavoriteLinks({
    required String submissionId,
    required OpenPostPageFetcher fetch,
  });

  Future<OpenPostActionResult> updateTagBlocklist({
    required String tagName,
    required bool shouldBlock,
    required String nonce,
    required String submissionId,
    required bool sfwEnabled,
  });

  Future<OpenPostActionResult> performBlockUnblock({
    required String urlPath,
    required String keyValue,
    required String linkUsername,
    required bool sfwEnabled,
  });

  Future<OpenPostActionResult> performWatchUnwatch({
    required String urlPath,
    required bool sfwEnabled,
  });

  Future<int?> sendAuthenticatedGet({
    required String url,
    required bool sfwEnabled,
  });

  Future<OpenPostDeletePrepareResult?> prepareDeletion({
    required String submissionId,
  });

  Future<bool?> confirmDeletion({
    required OpenPostDeleteConfirmationData confirmationData,
    required String password,
  });

  Future<bool> submitComment({
    required String message,
    required String submissionId,
  });

  Future<OpenPostMediaExportResult> exportToGallery(String imageUrl);

  Future<OpenPostMediaExportResult> shareFromUrl(String imageUrl);

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

  String buildChangeSubmissionUrl(String submissionId);

  String buildSubmissionViewUrl(String submissionId);

  String get troubleTicketsUrl;
}
