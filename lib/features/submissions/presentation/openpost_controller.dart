import 'package:fanotifier/features/submissions/domain/openpost_action_result.dart';
import 'package:fanotifier/features/submissions/domain/openpost_delete_models.dart';
import 'package:fanotifier/features/submissions/domain/openpost_details_load_result.dart';
import 'package:fanotifier/features/submissions/domain/openpost_favorite_links_load_result.dart';
import 'package:fanotifier/features/submissions/domain/openpost_file_download_result.dart';
import 'package:fanotifier/features/submissions/domain/openpost_media_export_result.dart';
import 'package:fanotifier/features/submissions/domain/openpost_models.dart';
import 'package:fanotifier/features/submissions/domain/openpost_page_response.dart';
import 'package:fanotifier/features/submissions/domain/openpost_repository.dart';
import 'package:fanotifier/features/submissions/domain/openpost_tag_block_state.dart';
import 'package:fanotifier/features/submissions/domain/openpost_submission_attachment.dart';
import 'package:flutter/foundation.dart';

class OpenPostController {
  OpenPostController({
    required this.submissionId,
    required this._repository,
  });

  final String submissionId;
  final OpenPostRepository _repository;

  String? profileImageUrl;
  String? username;
  String? linkUsername;
  String? submissionTitle;
  String? fullViewImageUrl;
  String? submissionDescription;
  DateTime? publicationTime;
  String? rating;
  int favoritesCount = 0;
  int viewCount = 0;
  int commentsCount = 0;
  List<Map<String, dynamic>> comments = <Map<String, dynamic>>[];
  String? userTimezoneIanaName;
  String? currentUsername;
  bool isDstCorrectionApplied = false;
  String? favLink;
  String? unfavLink;
  bool isFavorited = false;
  String? watchLink;
  String? unwatchLink;
  String? blockLink;
  String? unblockLink;
  bool isWatching = false;
  bool watchLinksLoading = false;
  bool isBlocked = false;
  String? category;
  String? type;
  String? species;
  String? gender;
  String? size;
  String? fileSize;
  List<String> keywords = <String>[];
  List<FaPostTag> keywordTags = <FaPostTag>[];
  List<FaPostTag> metaKeywordTags = <FaPostTag>[];
  String? tagBlocklistNonce;
  String? blockKey;
  String? unblockKey;
  bool isClassicUserPage = false;
  double? imageWidth;
  double? imageHeight;
  OpenPostSubmissionAttachment? submissionAttachment;
  bool isLoading = true;
  bool detailsLoaded = false;
  bool sfwEnabled = true;
  bool nsfwAllowed = false;

  Future<void> loadSfwEnabled() async {
    sfwEnabled = await _repository.loadSfwEnabled();
  }

  Future<OpenPostPageResponse> getWithSfwCookie(
    String url, {
    Map<String, String>? additionalHeaders,
    bool skipSfw = false,
    required Future<bool> Function() confirmNsfw,
    required void Function() onNsfwAllowed,
  }) async {
    final response = await _repository.fetchPage(
      url: url,
      sfwEnabled: sfwEnabled,
      nsfwAllowed: nsfwAllowed,
      additionalHeaders: additionalHeaders,
      skipSfw: skipSfw,
    );

    debugPrint('Response status: ${response.statusCode}');

    if (response.isHtml) {
      if (response.submissionNotFound) {
        debugPrint('DETECTED: Submission not found error');
        throw Exception('Submission not found in database');
      }

      if (!skipSfw) {
        if (response.matureContentWarning && !nsfwAllowed) {
          debugPrint(
              'DETECTED: Mature/Adult content warning - showing dialog');

          final userAgreed = await confirmNsfw();
          debugPrint('User response: $userAgreed');

          if (userAgreed) {
            nsfwAllowed = true;
            onNsfwAllowed();
            debugPrint('Retrying request with NSFW allowed');
            final retryResponse = await getWithSfwCookie(
              url,
              additionalHeaders: additionalHeaders,
              skipSfw: true,
              confirmNsfw: confirmNsfw,
              onNsfwAllowed: onNsfwAllowed,
            );
            debugPrint('Retry response status: ${retryResponse.statusCode}');
            return retryResponse;
          }

          debugPrint('User declined NSFW content');
          throw Exception('User declined to view NSFW content.');
        }

        if (response.oldMatureImageError && !nsfwAllowed) {
          debugPrint('DETECTED: Old style mature error - showing dialog');
          final userAgreed = await confirmNsfw();
          if (userAgreed) {
            nsfwAllowed = true;
            onNsfwAllowed();
            return getWithSfwCookie(
              url,
              additionalHeaders: additionalHeaders,
              skipSfw: true,
              confirmNsfw: confirmNsfw,
              onNsfwAllowed: onNsfwAllowed,
            );
          }
          throw Exception('User declined to view NSFW content.');
        }
      }
    }

    return response;
  }

  Future<bool> loadUserActions({
    required Future<bool> Function() confirmNsfw,
    required void Function() onNsfwAllowed,
  }) async {
    final author = username;
    if (author == null) return false;

    final result = await _repository.loadUserActions(
      author: author,
      fetch: (url) => getWithSfwCookie(
        url,
        confirmNsfw: confirmNsfw,
        onNsfwAllowed: onNsfwAllowed,
      ),
    );
    final actions = result.actions;
    if (actions == null) {
      debugPrint('Failed to fetch user page links: ${result.statusCode}');
      return false;
    }

    watchLink = actions.watchLink;
    unwatchLink = actions.unwatchLink;
    blockLink = actions.blockLink;
    unblockLink = actions.unblockLink;
    blockKey = actions.blockKey;
    unblockKey = actions.unblockKey;
    isClassicUserPage = actions.isClassic;
    isWatching = actions.isWatching;
    isBlocked = actions.isBlocked;
    return true;
  }

  void startLoading() {
    isLoading = true;
  }

  Future<bool> hasAuthCookies() {
    return _repository.hasAuthCookies();
  }

  void stopLoading() {
    isLoading = false;
  }

  Future<OpenPostDetailsLoadResult> loadDetails({
    required Future<bool> Function() confirmNsfw,
    required void Function() onNsfwAllowed,
  }) async {
    try {
      final result = await _repository.loadDetails(
        submissionId: submissionId,
        fetch: (url) => getWithSfwCookie(
          url,
          confirmNsfw: confirmNsfw,
          onNsfwAllowed: onNsfwAllowed,
        ),
      );

      if (result.status != OpenPostDetailsLoadStatus.success) {
        isLoading = false;
        return result;
      }

      _applyLoadedDetails(result.parsedPost!, result.comments!);
      return result;
    } catch (_) {
      isLoading = false;
      rethrow;
    }
  }

  void _applyLoadedDetails(
    OpenPostParseResult parsedPost,
    List<Map<String, dynamic>> parsedComments,
  ) {
    currentUsername = parsedPost.currentUsername;
    username = parsedPost.username;
    linkUsername = parsedPost.linkUsername;
    profileImageUrl = parsedPost.profileImageUrl;
    submissionTitle = parsedPost.submissionTitle;
    fullViewImageUrl = parsedPost.fullViewImageUrl;
    submissionDescription = parsedPost.submissionDescription;
    rating = parsedPost.rating;

    final publicationTimeRaw = parsedPost.publicationTimeRaw;
    if (publicationTimeRaw != null && publicationTimeRaw.isNotEmpty) {
      _parsePublicationTime(publicationTimeRaw);
    }

    favoritesCount = parsedPost.favoritesCount;
    viewCount = parsedPost.viewCount;
    commentsCount = parsedPost.commentsCount;
    favLink = parsedPost.favLink;
    unfavLink = parsedPost.unfavLink;
    isFavorited = parsedPost.isFavorited;
    category = parsedPost.category;
    type = parsedPost.type;
    species = parsedPost.species;
    gender = parsedPost.gender;
    size = parsedPost.size;
    fileSize = parsedPost.fileSize;
    keywords = parsedPost.keywords;
    keywordTags = parsedPost.keywordTags;
    metaKeywordTags = parsedPost.metaKeywordTags;
    tagBlocklistNonce = parsedPost.tagBlocklistNonce;
    imageWidth = parsedPost.imageWidth;
    imageHeight = parsedPost.imageHeight;
    submissionAttachment = parsedPost.submissionAttachment;
    comments = parsedComments;
    commentsCount = parsedComments.length;
    detailsLoaded = true;
    isLoading = false;
  }

  void _parsePublicationTime(String rawTime) {
    try {
      final parsed = _repository.parsePublicationTime(
        rawTime,
        applyDstCorrection: isDstCorrectionApplied,
      );
      if (parsed != null) {
        publicationTime = parsed;
        debugPrint('Successfully parsed FA date: $publicationTime');
        return;
      }

      debugPrint(
          "Could not parse date with any format. Raw string: '$rawTime'");
    } catch (error, stackTrace) {
      debugPrint('Error parsing publication time: $error');
      debugPrint("Raw time string was: '$rawTime'");
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<bool> loadFavoriteLinks({
    required Future<bool> Function() confirmNsfw,
    required void Function() onNsfwAllowed,
  }) async {
    final result = await _repository.loadFavoriteLinks(
      submissionId: submissionId,
      fetch: (url) => getWithSfwCookie(
        url,
        confirmNsfw: confirmNsfw,
        onNsfwAllowed: onNsfwAllowed,
      ),
    );

    if (result.status == OpenPostFavoriteLinksLoadStatus.success) {
      favLink = result.favoriteLink;
      unfavLink = result.unfavoriteLink;
      isFavorited = result.isFavorited;
      return true;
    }
    if (result.status == OpenPostFavoriteLinksLoadStatus.httpFailure) {
      debugPrint('Failed to fetch favorite links: ${result.statusCode}');
    }
    return false;
  }

  bool applyLocalTagBlockState(
    String tagName, {
    required bool isBlocked,
  }) {
    final result = updateOpenPostTagBlockState(
      keywordTags: keywordTags,
      metaKeywordTags: metaKeywordTags,
      tagName: tagName,
      isBlocked: isBlocked,
    );
    if (!result.updated) return false;
    keywordTags = result.keywordTags;
    metaKeywordTags = result.metaKeywordTags;
    return true;
  }

  Future<void> updateTagBlocklist(
    String tagName, {
    required bool shouldBlock,
  }) async {
    final nonce = tagBlocklistNonce;
    if (nonce == null || nonce.isEmpty) {
      throw Exception('Missing tag blocklist nonce.');
    }

    final result = await _repository.updateTagBlocklist(
      tagName: tagName,
      shouldBlock: shouldBlock,
      nonce: nonce,
      submissionId: submissionId,
      sfwEnabled: sfwEnabled,
    );
    if (result.status == OpenPostActionStatus.missingAuth) {
      throw Exception('Not logged in.');
    }
    if (result.status != OpenPostActionStatus.success) {
      throw Exception('Tag blocklist request failed: ${result.statusCode}');
    }
  }

  String? blockActionKey({required bool shouldBlock}) {
    return shouldBlock
        ? _repository.extractActionKey(blockLink ?? '', blockKey)
        : _repository.extractActionKey(unblockLink ?? '', unblockKey);
  }

  Future<OpenPostActionResult> performBlockUnblock(
    String urlPath,
    String keyValue,
  ) {
    return _repository.performBlockUnblock(
      urlPath: urlPath,
      keyValue: keyValue,
      linkUsername: linkUsername ?? '',
      sfwEnabled: sfwEnabled,
    );
  }

  Future<OpenPostActionResult> performWatchUnwatch(String urlPath) {
    return _repository.performWatchUnwatch(
      urlPath: urlPath,
      sfwEnabled: sfwEnabled,
    );
  }

  Future<int?> sendAuthenticatedGet(String url) {
    return _repository.sendAuthenticatedGet(
      url: url,
      sfwEnabled: sfwEnabled,
    );
  }

  Future<OpenPostDeletePrepareResult?> prepareDeletion() {
    return _repository.prepareDeletion(submissionId: submissionId);
  }

  Future<bool?> confirmDeletion({
    required OpenPostDeleteConfirmationData confirmationData,
    required String password,
  }) {
    return _repository.confirmDeletion(
      confirmationData: confirmationData,
      password: password,
    );
  }

  void setWatchLinksLoading(bool value) {
    watchLinksLoading = value;
  }

  void addComment(String commentText) {
    comments = <Map<String, dynamic>>[
      ...comments,
      <String, dynamic>{
        'profileImage': null,
        'username': 'You',
        'text': commentText,
        'width': 100.0,
        'isOP': false,
      },
    ];
    commentsCount += 1;
  }

  void toggleFavoriteLocally(bool isFavorited) {
    this.isFavorited = isFavorited;
    favoritesCount += isFavorited ? 1 : -1;
  }

  Future<bool> sendFavoriteRequest({
    required bool shouldFavorite,
    required Future<bool> Function() confirmNsfw,
    required void Function() onNsfwAllowed,
  }) async {
    final relativeUrl = shouldFavorite ? favLink : unfavLink;
    if (relativeUrl == null) return false;

    try {
      final result = await _repository.performWatchUnwatch(
        urlPath: relativeUrl,
        sfwEnabled: sfwEnabled,
      );
      if (result.status == OpenPostActionStatus.missingAuth) return false;
      if (result.status == OpenPostActionStatus.success) {
        return loadFavoriteLinks(
          confirmNsfw: confirmNsfw,
          onNsfwAllowed: onNsfwAllowed,
        );
      }
      debugPrint('Failed to toggle favorite: ${result.statusCode}');
    } catch (error) {
      debugPrint('Error toggling favorite: $error');
    }
    return false;
  }

  Future<bool> submitComment(String commentText) {
    return _repository.submitComment(
      message: commentText,
      submissionId: submissionId,
    );
  }

  Future<OpenPostMediaExportResult> exportToGallery(String imageUrl) {
    return _repository.exportToGallery(imageUrl);
  }

  Future<OpenPostMediaExportResult> shareFromUrl(String imageUrl) {
    return _repository.shareFromUrl(imageUrl);
  }

  Future<OpenPostFileDownloadResult> downloadSubmissionFile(
    OpenPostSubmissionAttachment attachment,
  ) {
    return _repository.downloadSubmissionFile(
      attachment: attachment,
      sfwEnabled: sfwEnabled,
      nsfwAllowed: nsfwAllowed,
    );
  }

  String normalizeSubmissionHtml(String htmlContent) {
    return _repository.replaceTruncatedSubmissionLinks(htmlContent);
  }

  String? findFullCommentLink(String commentHtml, String truncatedUrl) {
    return _repository.findFullShortenedCommentLink(
      commentHtml,
      truncatedUrl,
    );
  }

  String buildChangeInfoUrl() {
    return _repository.buildChangeInfoUrl(submissionId);
  }

  String buildChangeSubmissionUrl() {
    return _repository.buildChangeSubmissionUrl(submissionId);
  }

  String get submissionViewUrl {
    return _repository.buildSubmissionViewUrl(submissionId);
  }

  String get troubleTicketsUrl => _repository.troubleTicketsUrl;
}
