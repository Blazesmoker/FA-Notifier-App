import 'package:fanotifier/features/submissions/domain/submission_action_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_delete_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_details_load_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_file_download_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_media_export_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_document_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_page_response.dart';
import 'package:fanotifier/features/submissions/domain/submission_details_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_tag_block_state.dart';
import 'package:fanotifier/features/submissions/domain/submission_attachment.dart';
import 'package:flutter/foundation.dart';

enum SubmissionWatchOutcome { missingAuth, success, failed, error }

class SubmissionDetailsController {
  SubmissionDetailsController({
    required this.submissionId,
    required this._repository,
    required this._isMounted,
    required this._updateState,
    required this._reloadUserActions,
    required this._reloadDetails,
    required this._showActionMessage,
  });

  final bool Function() _isMounted;
  final void Function(VoidCallback update) _updateState;
  final Future<void> Function() _reloadUserActions;
  final Future<void> Function() _reloadDetails;
  final void Function(String message, {required bool isError}) _showActionMessage;
  final Set<String> _tagToggleInFlight = <String>{};
  Set<String> get tagToggleInFlight => _tagToggleInFlight;

  final String submissionId;
  final SubmissionDetailsRepository _repository;

  String? _profileImageUrl;
  String? _username;
  String? _linkUsername;
  String? _submissionTitle;
  String? _fullViewImageUrl;
  String? _submissionDescription;
  DateTime? _publicationTime;
  String? _rating;
  int _favoritesCount = 0;
  int _viewCount = 0;
  int _commentsCount = 0;
  List<Map<String, dynamic>> _comments = <Map<String, dynamic>>[];
  String? _userTimezoneIanaName;
  String? _currentUsername;
  final bool _isDstCorrectionApplied = false;
  String? _favLink;
  String? _unfavLink;
  bool _isFavorited = false;
  String? _watchLink;
  String? _unwatchLink;
  String? _blockLink;
  String? _unblockLink;
  bool _isWatching = false;
  bool _watchLinksLoading = false;
  bool _watchRequestInFlight = false;
  bool _isBlocked = false;
  String? _category;
  String? _type;
  String? _species;
  String? _gender;
  String? _size;
  String? _fileSize;
  List<SubmissionFolderLink> _folders = <SubmissionFolderLink>[];
  List<String> _keywords = <String>[];
  List<FaPostTag> _keywordTags = <FaPostTag>[];
  List<FaPostTag> _metaKeywordTags = <FaPostTag>[];
  String? _tagBlocklistNonce;
  String? _blockKey;
  String? _unblockKey;
  bool _isClassicUserPage = false;
  double? _imageWidth;
  double? _imageHeight;
  SubmissionAttachment? _submissionAttachment;
  bool _isLoading = true;
  bool _detailsLoaded = false;
  bool _sfwEnabled = true;
  bool _nsfwAllowed = false;

  String? get profileImageUrl => _profileImageUrl;
  String? get username => _username;
  String? get linkUsername => _linkUsername;
  String? get submissionTitle => _submissionTitle;
  String? get fullViewImageUrl => _fullViewImageUrl;
  String? get submissionDescription => _submissionDescription;
  DateTime? get publicationTime => _publicationTime;
  String? get rating => _rating;
  int get favoritesCount => _favoritesCount;
  int get viewCount => _viewCount;
  int get commentsCount => _commentsCount;
  List<Map<String, dynamic>> get comments => _comments;
  String? get userTimezoneIanaName => _userTimezoneIanaName;
  String? get currentUsername => _currentUsername;
  bool get isDstCorrectionApplied => _isDstCorrectionApplied;
  String? get favLink => _favLink;
  String? get unfavLink => _unfavLink;
  bool get isFavorited => _isFavorited;
  String? get watchLink => _watchLink;
  String? get unwatchLink => _unwatchLink;
  String? get blockLink => _blockLink;
  String? get unblockLink => _unblockLink;
  bool get isWatching => _isWatching;
  bool get watchLinksLoading => _watchLinksLoading;
  bool get watchRequestInFlight => _watchRequestInFlight;
  bool get isBlocked => _isBlocked;
  String? get category => _category;
  String? get type => _type;
  String? get species => _species;
  String? get gender => _gender;
  String? get size => _size;
  String? get fileSize => _fileSize;
  List<SubmissionFolderLink> get folders => _folders;
  List<String> get keywords => _keywords;
  List<FaPostTag> get keywordTags => _keywordTags;
  List<FaPostTag> get metaKeywordTags => _metaKeywordTags;
  String? get tagBlocklistNonce => _tagBlocklistNonce;
  String? get blockKey => _blockKey;
  String? get unblockKey => _unblockKey;
  bool get isClassicUserPage => _isClassicUserPage;
  double? get imageWidth => _imageWidth;
  double? get imageHeight => _imageHeight;
  SubmissionAttachment? get submissionAttachment => _submissionAttachment;
  bool get isLoading => _isLoading;
  bool get detailsLoaded => _detailsLoaded;
  bool get sfwEnabled => _sfwEnabled;
  bool get nsfwAllowed => _nsfwAllowed;

  Future<void> toggleTagBlock(FaPostTag tag) async {
    if (_tagToggleInFlight.contains(tag.name)) return;

    if (tagBlocklistNonce == null || tagBlocklistNonce!.isEmpty) {
      _showActionMessage(
        'Tag blocking is unavailable right now (missing nonce).',
        isError: true,
      );
      return;
    }

    _updateState(() => _tagToggleInFlight.add(tag.name));

    try {
      final shouldBlock = !tag.isBlocked;
      await _sendTagBlocklistRequest(tag.name, shouldBlock: shouldBlock);

      // Update UI immediately so +/− changes without waiting for a full refresh.
      _applyLocalTagBlockState(tag.name, isBlocked: shouldBlock);

      // Refresh so the block/unblock state and blocked-content markers match FA.
      await _reloadDetails();

      // If the refreshed HTML didn't reflect the change yet, keep UI consistent.
      _applyLocalTagBlockState(tag.name, isBlocked: shouldBlock);

      if (!_isMounted()) return;
      _showActionMessage(
        shouldBlock
            ? 'Tag blocked: ${tag.name}'
            : 'Tag unblocked: ${tag.name}',
        isError: false,
      );
    } catch (e) {
      if (!_isMounted()) return;
      _showActionMessage(
        'Failed to ${tag.isBlocked ? 'unblock' : 'block'} tag: ${tag.name}',
        isError: true,
      );
    } finally {
      if (_isMounted()) _updateState(() => _tagToggleInFlight.remove(tag.name));
    }
  }

  void _applyLocalTagBlockState(String tagName, {required bool isBlocked}) {
    final updated = applyLocalTagBlockState(
      tagName,
      isBlocked: isBlocked,
    );
    if (updated) _updateState(() {});
  }

  Future<void> _sendTagBlocklistRequest(String tagName,
      {required bool shouldBlock}) {
    return updateTagBlocklist(
      tagName,
      shouldBlock: shouldBlock,
    );
  }

  Future<void> toggleAuthorBlock() async {
    // When we skipped initial fetch, load links on first use (same as Watch)
    if (blockLink == null && unblockLink == null && username != null) {
      _updateState(() => _watchLinksLoading = true);
      await _reloadUserActions();
      if (!_isMounted()) return;
      _updateState(() => _watchLinksLoading = false);
    }
    if (isBlocked) {
      if (unblockLink == null) {
        _showActionMessage(
          'Cannot unblock author at this time.',
          isError: true,
        );
        return;
      }
      final key = blockActionKey(shouldBlock: false);
      if (key == null || key.isEmpty) {
        _showActionMessage(
          'Unblock key is missing.',
          isError: true,
        );
        return;
      }
      await _sendBlockUnblockPostRequest('/unblock/$linkUsername/', key,
          shouldBlock: false);
    } else {
      if (blockLink == null) {
        _showActionMessage(
          'Cannot block author at this time.',
          isError: true,
        );
        return;
      }
      final key = blockActionKey(shouldBlock: true);
      if (key == null || key.isEmpty) {
        _showActionMessage(
          'Block key is missing.',
          isError: true,
        );
        return;
      }
      await _sendBlockUnblockPostRequest('/block/$linkUsername/', key,
          shouldBlock: true);
    }
  }

  Future<void> _sendBlockUnblockPostRequest(String urlPath, String keyValue,
      {required bool shouldBlock}) async {
    try {
      final result = await performBlockUnblock(urlPath, keyValue);

      if (!_isMounted()) return;
      if (result.status == SubmissionActionStatus.missingAuth) {
        _showActionMessage(
          'Please log in to perform this action.',
          isError: true,
        );
        return;
      }

      if (result.status == SubmissionActionStatus.success) {
        await _reloadUserActions();
        if (!_isMounted()) return;
        _showActionMessage(
          shouldBlock ? 'Author blocked' : 'Author unblocked',
          isError: false,
        );
      } else {
        _showActionMessage(
          'Failed to ${shouldBlock ? 'block' : 'unblock'} author.',
          isError: true,
        );
      }
    } catch (e) {
      if (!_isMounted()) return;
      _showActionMessage(
        'An error occurred while trying to ${shouldBlock ? 'block' : 'unblock'} author.',
        isError: true,
      );
    }
  }

  Future<SubmissionWatchOutcome> _sendWatchUnwatchRequest(String urlPath,
      {required bool shouldWatch}) async {
    try {
      final result = await performWatchUnwatch(urlPath);
      if (result.status == SubmissionActionStatus.missingAuth) {
        return SubmissionWatchOutcome.missingAuth;
      }
      if (result.status == SubmissionActionStatus.success) {
        await _reloadUserActions();
        return SubmissionWatchOutcome.success;
      }
      debugPrint(
          'Failed to ${shouldWatch ? 'watch' : 'unwatch'} user. Status code: ${result.statusCode}');
      return SubmissionWatchOutcome.failed;
    } catch (e) {
      debugPrint('Error during ${shouldWatch ? 'watch' : 'unwatch'}: $e');
      return SubmissionWatchOutcome.error;
    }
  }

  Future<void> toggleWatch({
    required void Function(
      SubmissionWatchOutcome outcome, {
      required bool shouldWatch,
    }) onOutcome,
  }) async {
    if (_watchRequestInFlight) return;
    // When we skipped initial fetch (Browse/Search), fetch links on first tap
    if (watchLink == null && unwatchLink == null && username != null) {
      if (_watchLinksLoading) return;
      _updateState(() => _watchLinksLoading = true);
      await _reloadUserActions();
      if (!_isMounted()) return;
      _updateState(() => _watchLinksLoading = false);
      // After fetch: if already watching, button will show -Watch; else send watch request below
    }
    _updateState(() => _watchRequestInFlight = true);
    final shouldWatch = !isWatching;
    var outcome = SubmissionWatchOutcome.failed;
    try {
      if (isWatching) {
        if (unwatchLink == null) return;
        outcome =
            await _sendWatchUnwatchRequest(unwatchLink!, shouldWatch: false);
      } else {
        if (watchLink == null) return;
        outcome =
            await _sendWatchUnwatchRequest(watchLink!, shouldWatch: true);
      }
    } finally {
      if (_isMounted()) {
        _updateState(() => _watchRequestInFlight = false);
      }
    }
    onOutcome(outcome, shouldWatch: shouldWatch);
  }

  Future<void> loadSfwEnabled() async {
    _sfwEnabled = await _repository.loadSfwEnabled();
  }

  Future<SubmissionPageResponse> getWithSfwCookie(
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
            _nsfwAllowed = true;
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
            _nsfwAllowed = true;
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

    _watchLink = actions.watchLink;
    _unwatchLink = actions.unwatchLink;
    _blockLink = actions.blockLink;
    _unblockLink = actions.unblockLink;
    _blockKey = actions.blockKey;
    _unblockKey = actions.unblockKey;
    _isClassicUserPage = actions.isClassic;
    _isWatching = actions.isWatching;
    _isBlocked = actions.isBlocked;
    return true;
  }

  void startLoading() {
    _isLoading = true;
  }

  Future<bool> hasAuthCookies() {
    return _repository.hasAuthCookies();
  }

  void stopLoading() {
    _isLoading = false;
  }

  Future<SubmissionDetailsLoadResult> loadDetails({
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

      if (result.status != SubmissionDetailsLoadStatus.success) {
        _isLoading = false;
        return result;
      }

      _applyLoadedDetails(result.parsedPost!, result.comments!);
      return result;
    } catch (_) {
      _isLoading = false;
      rethrow;
    }
  }

  void _applyLoadedDetails(
    SubmissionParseResult parsedPost,
    List<Map<String, dynamic>> parsedComments,
  ) {
    _currentUsername = parsedPost.currentUsername;
    _username = parsedPost.username;
    _linkUsername = parsedPost.linkUsername;
    _profileImageUrl = parsedPost.profileImageUrl;
    _submissionTitle = parsedPost.submissionTitle;
    _fullViewImageUrl = parsedPost.fullViewImageUrl;
    _submissionDescription = parsedPost.submissionDescription;
    _rating = parsedPost.rating;

    final publicationTimeRaw = parsedPost.publicationTimeRaw;
    if (publicationTimeRaw != null && publicationTimeRaw.isNotEmpty) {
      _parsePublicationTime(publicationTimeRaw);
    }

    _favoritesCount = parsedPost.favoritesCount;
    _viewCount = parsedPost.viewCount;
    _commentsCount = parsedPost.commentsCount;
    _favLink = parsedPost.favLink;
    _unfavLink = parsedPost.unfavLink;
    _isFavorited = parsedPost.isFavorited;
    _category = parsedPost.category;
    _type = parsedPost.type;
    _species = parsedPost.species;
    _gender = parsedPost.gender;
    _size = parsedPost.size;
    _fileSize = parsedPost.fileSize;
    _folders = parsedPost.folders;
    _keywords = parsedPost.keywords;
    _keywordTags = parsedPost.keywordTags;
    _metaKeywordTags = parsedPost.metaKeywordTags;
    _tagBlocklistNonce = parsedPost.tagBlocklistNonce;
    _imageWidth = parsedPost.imageWidth;
    _imageHeight = parsedPost.imageHeight;
    _submissionAttachment = parsedPost.submissionAttachment;
    _comments = parsedComments;
    _commentsCount = parsedComments.length;
    _detailsLoaded = true;
    _isLoading = false;
  }

  void _parsePublicationTime(String rawTime) {
    try {
      final parsed = _repository.parsePublicationTime(
        rawTime,
        applyDstCorrection: isDstCorrectionApplied,
      );
      if (parsed != null) {
        _publicationTime = parsed;
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

  bool applyLocalTagBlockState(
    String tagName, {
    required bool isBlocked,
  }) {
    final result = updateSubmissionTagBlockState(
      keywordTags: keywordTags,
      metaKeywordTags: metaKeywordTags,
      tagName: tagName,
      isBlocked: isBlocked,
    );
    if (!result.updated) return false;
    _keywordTags = result.keywordTags;
    _metaKeywordTags = result.metaKeywordTags;
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
    if (result.status == SubmissionActionStatus.missingAuth) {
      throw Exception('Not logged in.');
    }
    if (result.status != SubmissionActionStatus.success) {
      throw Exception('Tag blocklist request failed: ${result.statusCode}');
    }
  }

  String? blockActionKey({required bool shouldBlock}) {
    return shouldBlock
        ? _repository.extractActionKey(blockLink ?? '', blockKey)
        : _repository.extractActionKey(unblockLink ?? '', unblockKey);
  }

  Future<SubmissionActionResult> performBlockUnblock(
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

  Future<SubmissionActionResult> performWatchUnwatch(String urlPath) {
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

  Future<SubmissionDeletePrepareResult?> prepareDeletion() {
    return _repository.prepareDeletion(submissionId: submissionId);
  }

  Future<bool?> confirmDeletion({
    required SubmissionDeleteConfirmationData confirmationData,
    required String password,
  }) {
    return _repository.confirmDeletion(
      confirmationData: confirmationData,
      password: password,
    );
  }

  void addComment(String commentText) {
    _comments = <Map<String, dynamic>>[
      ...comments,
      <String, dynamic>{
        'profileImage': null,
        'username': 'You',
        'text': commentText,
        'width': 100.0,
        'isOP': false,
      },
    ];
    _commentsCount += 1;
  }

  Future<bool> submitComment(String commentText) {
    return _repository.submitComment(
      message: commentText,
      submissionId: submissionId,
    );
  }

  Future<SubmissionMediaExportResult> exportToGallery(String imageUrl) {
    return _repository.exportToGallery(imageUrl);
  }

  Future<SubmissionMediaExportResult> shareFromUrl(String imageUrl) {
    return _repository.shareFromUrl(imageUrl);
  }

  Future<SubmissionFileDownloadResult> downloadSubmissionFile(
    SubmissionAttachment attachment,
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

  String buildChangeThumbnailUrl() {
    return _repository.buildChangeThumbnailUrl(submissionId);
  }

  String buildChangeSubmissionUrl() {
    return _repository.buildChangeSubmissionUrl(submissionId);
  }

  String get submissionViewUrl {
    return _repository.buildSubmissionViewUrl(submissionId);
  }

  String get troubleTicketsUrl => _repository.troubleTicketsUrl;
}
