import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/submissions/data/openpost_action_service.dart';
import 'package:FANotifier/features/submissions/data/openpost_cookie_service.dart';
import 'package:FANotifier/features/submissions/data/openpost_details_loader.dart';
import 'package:FANotifier/features/submissions/data/openpost_favorite_links_loader.dart';
import 'package:FANotifier/features/submissions/data/openpost_html_parser.dart';
import 'package:FANotifier/features/submissions/data/openpost_link_parser.dart';
import 'package:FANotifier/features/submissions/data/openpost_url_builder.dart';
import 'package:FANotifier/features/submissions/data/openpost_user_actions_loader.dart';
import 'package:FANotifier/features/submissions/data/submission_publication_time_parser.dart';
import 'package:FANotifier/features/submissions/domain/openpost_action_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_delete_models.dart';
import 'package:FANotifier/features/submissions/domain/openpost_details_load_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_favorite_links_load_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_models.dart';
import 'package:FANotifier/features/submissions/domain/openpost_tag_block_state.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

class OpenPostController {
  OpenPostController({
    required this.submissionId,
    OpenPostActionService actionService = const OpenPostActionService(),
    OpenPostCookieService cookieService = const OpenPostCookieService(),
    SfwModePreference sfwModePreference = const SfwModePreference(),
    OpenPostDetailsLoader detailsLoader = const OpenPostDetailsLoader(),
    OpenPostUserActionsLoader userActionsLoader =
        const OpenPostUserActionsLoader(),
  })  : _actionService = actionService,
        _cookieService = cookieService,
        _sfwModePreference = sfwModePreference,
        _detailsLoader = detailsLoader,
        _userActionsLoader = userActionsLoader;

  final String submissionId;
  final OpenPostActionService _actionService;
  final OpenPostCookieService _cookieService;
  final SfwModePreference _sfwModePreference;
  final OpenPostDetailsLoader _detailsLoader;
  final OpenPostUserActionsLoader _userActionsLoader;

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
  bool isLoading = true;
  bool detailsLoaded = false;
  bool sfwEnabled = true;
  bool nsfwAllowed = false;

  Future<void> loadSfwEnabled() async {
    sfwEnabled = await _sfwModePreference.loadSfwEnabled();
  }

  Future<Response> getWithSfwCookie(
    String url, {
    Map<String, String>? additionalHeaders,
    bool skipSfw = false,
    required Future<bool> Function() confirmNsfw,
    required void Function() onNsfwAllowed,
  }) async {
    final response = await _cookieService.getWithSfwCookie(
      url: url,
      sfwEnabled: sfwEnabled,
      nsfwAllowed: nsfwAllowed,
      additionalHeaders: additionalHeaders,
      skipSfw: skipSfw,
    );

    debugPrint('Response status: ${response.statusCode}');

    final contentType =
        (response.headers['content-type'] ?? '').toLowerCase();
    if (response.statusCode == 200 &&
        (contentType.contains('text/html') ||
            contentType.contains('application/xhtml'))) {
      final decodedBody = decodeOpenPostResponseBody(response.bodyBytes);

      if (hasSubmissionNotFoundError(decodedBody)) {
        debugPrint('DETECTED: Submission not found error');
        throw Exception('Submission not found in database');
      }

      if (!skipSfw) {
        if (hasMatureContentWarning(decodedBody) && !nsfwAllowed) {
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

        if (hasOldMatureImageError(decodedBody) && !nsfwAllowed) {
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
    required Future<Response> Function(String url) fetch,
  }) async {
    final author = username;
    if (author == null) return false;

    final result = await _userActionsLoader.load(
      url: buildOpenPostUserUrl(author),
      fetch: fetch,
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
    return _cookieService.hasAuthCookies();
  }

  void stopLoading() {
    isLoading = false;
  }

  Future<OpenPostDetailsLoadResult> loadDetails({
    required Future<Response> Function(String url) fetch,
  }) async {
    try {
      final result = await _detailsLoader.load(
        url: buildSubmissionViewUrl(submissionId),
        fetch: fetch,
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
    comments = parsedComments;
    commentsCount = parsedComments.length;
    detailsLoaded = true;
    isLoading = false;
  }

  void _parsePublicationTime(String rawTime) {
    try {
      final parsed = parseSubmissionPublicationTime(
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
    required Future<Response> Function(String url) fetch,
  }) async {
    final result = await OpenPostFavoriteLinksLoader(
      cookieService: _cookieService,
    ).load(
      url: buildSubmissionViewUrl(submissionId),
      fetch: fetch,
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

    final result = await _actionService.performTagBlocklistRequest(
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
        ? extractOpenPostActionKey(blockLink ?? '', blockKey)
        : extractOpenPostActionKey(unblockLink ?? '', unblockKey);
  }

  Future<OpenPostActionResult> performBlockUnblock(
    String urlPath,
    String keyValue,
  ) {
    return _actionService.performBlockUnblockRequest(
      urlPath: urlPath,
      keyValue: keyValue,
      linkUsername: linkUsername ?? '',
      sfwEnabled: sfwEnabled,
    );
  }

  Future<OpenPostActionResult> performWatchUnwatch(String urlPath) {
    return _actionService.performAuthenticatedGet(
      url: buildOpenPostAbsolutePath(urlPath),
      sfwEnabled: sfwEnabled,
    );
  }

  Future<int?> sendAuthenticatedGet(String url) {
    return _actionService.sendAuthenticatedGet(
      url: url,
      sfwEnabled: sfwEnabled,
    );
  }

  Future<OpenPostDeletePrepareResult?> prepareDeletion() {
    return _actionService.prepareDeletion(submissionId: submissionId);
  }

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

  void setWatchLinksLoading(bool value) {
    watchLinksLoading = value;
  }

  void addComment(String commentText) {
    comments.add(<String, dynamic>{
      'profileImage': null,
      'username': 'You',
      'text': commentText,
      'width': 100.0,
      'isOP': false,
    });
    commentsCount += 1;
  }

  void toggleFavoriteLocally(bool isFavorited) {
    this.isFavorited = isFavorited;
    favoritesCount += isFavorited ? 1 : -1;
  }

  Future<bool> sendFavoriteRequest({
    required bool shouldFavorite,
    required Future<Response> Function(String url) fetch,
  }) async {
    final relativeUrl = shouldFavorite ? favLink : unfavLink;
    if (relativeUrl == null) return false;

    try {
      final statusCode = await _actionService.sendAuthenticatedGet(
        url: buildOpenPostAbsolutePath(relativeUrl),
        sfwEnabled: sfwEnabled,
      );
      if (statusCode == null) return false;
      if (statusCode == 200) {
        return loadFavoriteLinks(fetch: fetch);
      }
      debugPrint('Failed to toggle favorite: $statusCode');
    } catch (error) {
      debugPrint('Error toggling favorite: $error');
    }
    return false;
  }
}
