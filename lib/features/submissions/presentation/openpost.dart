import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/scheduler.dart';
import 'package:FANotifier/features/notes/presentation/reply_screen.dart';
import 'package:flutter/material.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:like_button/like_button.dart';
import 'package:FANotifier/app/app_theme.dart';
import 'package:FANotifier/main.dart';
import 'package:FANotifier/shared/fa/fa_username.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/utils/comment_composer_lines.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/comments/data/submission_comment_service.dart';
import 'package:FANotifier/features/submissions/data/openpost_action_service.dart';
import 'package:FANotifier/features/submissions/data/openpost_cookie_service.dart';
import 'package:FANotifier/features/submissions/data/openpost_details_loader.dart';
import 'package:FANotifier/features/submissions/data/openpost_favorite_links_loader.dart';
import 'package:FANotifier/features/submissions/data/openpost_user_actions_loader.dart';
import 'package:FANotifier/features/submissions/data/openpost_link_parser.dart';
import 'package:FANotifier/features/submissions/data/openpost_url_builder.dart';
import 'package:FANotifier/features/submissions/data/openpost_html_parser.dart';
import 'package:FANotifier/features/submissions/data/openpost_media_export_service.dart';
import 'package:FANotifier/features/submissions/data/submission_publication_time_parser.dart';
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/submissions/presentation/SubmissionDescriptionWebview.dart';
import 'package:FANotifier/features/profile/presentation/image_inspect_screen.dart';
import 'package:FANotifier/features/submissions/domain/openpost_models.dart';
import 'package:FANotifier/features/submissions/domain/openpost_details_load_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_favorite_links_load_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_media_export_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_action_result.dart';
import 'package:FANotifier/features/submissions/domain/openpost_tag_block_state.dart';
import 'package:FANotifier/features/submissions/domain/openpost_delete_models.dart';
import 'package:FANotifier/features/submissions/presentation/edit_submission_screen.dart';
import 'package:FANotifier/features/comments/presentation/editcommentscreen.dart';
import 'package:FANotifier/features/search/presentation/keyword_search_screen.dart';
import 'package:FANotifier/features/notes/presentation/new_message.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:FANotifier/features/journals/presentation/openjournal.dart';
import 'package:FANotifier/features/submissions/presentation/openpost_comments.dart';
import 'package:FANotifier/features/profile/domain/profile_section.dart';
import 'package:FANotifier/features/settings/data/translator_settings_provider.dart';
import 'package:FANotifier/shared/utils/fa_link_matcher.dart';
import 'package:FANotifier/shared/navigation/detachable_webview_route_registry.dart';
import 'package:FANotifier/shared/translation/ios_scroll_recovery.dart';
import 'package:FANotifier/shared/translation/native_translate_launcher.dart';
import 'package:FANotifier/shared/translation/translation_service.dart';
import 'package:FANotifier/shared/translation/translation_source_text_builder.dart';
import 'package:FANotifier/shared/platform/fa_share_service.dart';
import 'package:provider/provider.dart';

class _TransparentOpenPostPageRoute<T> extends PageRoute<T> {
  _TransparentOpenPostPageRoute({
    required this.builder,
    super.settings,
    super.requestFocus,
    this.maintainState = true,
    this.routeTransitionDuration = const Duration(milliseconds: 280),
    this.routeReverseTransitionDuration = const Duration(milliseconds: 280),
  });

  final WidgetBuilder builder;
  @override
  final bool maintainState;
  final Duration routeTransitionDuration;
  final Duration routeReverseTransitionDuration;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => routeTransitionDuration;

  @override
  Duration get reverseTransitionDuration => routeReverseTransitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: animation.drive(
        Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
      ),
      child: child,
    );
  }
}

class OpenPost extends StatefulWidget {
  final String imageUrl;
  final String uniqueNumber;
  final bool skipInitialWatchCheck;

  const OpenPost({
    required this.imageUrl,
    required this.uniqueNumber,
    this.skipInitialWatchCheck = false,
    Key? key,
  }) : super(key: key);

  static Route<T> route<T>({
    required String imageUrl,
    required String uniqueNumber,
    bool skipInitialWatchCheck = false,
    RouteSettings? settings,
  }) {
    final builder = (BuildContext context) => OpenPost(
          imageUrl: imageUrl,
          uniqueNumber: uniqueNumber,
          skipInitialWatchCheck: skipInitialWatchCheck,
        );

    if (Platform.isAndroid || Platform.isIOS) {
      return _TransparentOpenPostPageRoute<T>(
        settings: settings,
        builder: builder,
      );
    }

    return MaterialPageRoute<T>(settings: settings, builder: builder);
  }

  @override
  _OpenPostState createState() => _OpenPostState();
}

class _OpenPostState extends State<OpenPost>
    with RouteAware, WidgetsBindingObserver, TickerProviderStateMixin
    implements DetachableWebViewRouteOwner {
  bool _showFullPublicationDate = false;
  String? profileImageUrl;
  String? username;
  String? linkUsername;
  String? submissionTitle;
  String? fullViewImageUrl;
  String? submissionDescription;
  DateTime? publicationTime;
  String? rating; // "general" | "mature" | "adult" | null
  int favoritesCount = 0;
  int viewCount = 0;
  int commentsCount = 0;
  List<Map<String, dynamic>> comments = [];
  late final OpenPostActionService _openPostActionService;
  final OpenPostCookieService _openPostCookieService =
      const OpenPostCookieService();
  final SfwModePreference _sfwModePreference = SfwModePreference();
  late final PostCommentService _postCommentService;
  final OpenPostMediaExportService _openPostMediaExportService =
      const OpenPostMediaExportService();
  final TranslationService _translationService = TranslationService.instance;
  final TranslationSourceTextBuilder _translationSourceTextBuilder =
      TranslationSourceTextBuilder(TranslationService.instance);
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _commentComposerFocusRequestedByUser = false;
  bool _blockRestoredCommentComposerFocus = true;
  Timer? _debounceTimer;
  bool _pendingFavoriteState = false;
  String? userTimezoneIanaName;
  String? currentUsername;
  bool isDstCorrectionApplied = false;
  String? favLink;
  String? unfavLink;
  bool isFavorited = false;
  String? watchLink;
  String? unwatchLink;
  String? blockLink;
  bool isWatching = false;
  bool _watchLinksLoading = false;
  String? unblockLink;
  bool isBlocked = false;
  String? category;
  String? type;
  String? species;
  String? gender;
  String? size;
  String? fileSize;
  List<String> keywords = [];
  List<FaPostTag> keywordTags = [];
  List<FaPostTag> metaKeywordTags = [];
  String? tagBlocklistNonce;
  bool _showTagsSection = false;
  final Set<String> _tagToggleInFlight = <String>{};
  final ValueNotifier<bool> _showScrollToTopNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isSendingInlineComment =
      ValueNotifier<bool>(false);
  final ValueNotifier<double> _keyboardInset = ValueNotifier<double>(0);
  final ValueNotifier<bool> _isCommentComposerExpanded =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> _commentDraftHasText = ValueNotifier<bool>(false);
  final ValueNotifier<int> _commentDraftCollapsedLines = ValueNotifier<int>(1);
  String? _blockKey;
  String? _unblockKey;
  bool _isClassicUserPage = false;
  bool _isPostWebViewDetached = false;
  bool _suppressNextRouteDetach = false;
  bool _enableScrollWebViewPause = false;
  int _frameTimingCount = 0;
  int _frameTimingTotalMicros = 0;
  double? imageWidth;
  double? imageHeight;
  bool isLoading = true;
  bool _detailsLoaded = false;
  bool _webViewLoaded = false;
  bool _sfwEnabled = true;
  bool _nsfwAllowed = false;
  final GlobalKey<SubmissionDescriptionWebViewState> _submissionWebViewKey =
      GlobalKey<SubmissionDescriptionWebViewState>();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<SelectionAreaState> _titleSelectionKey = GlobalKey();
  final Map<Object, GlobalKey<SelectionAreaState>> _commentSelectionKeys =
      <Object, GlobalKey<SelectionAreaState>>{};
  final Map<Object, String> _commentSelectedTexts = <Object, String>{};
  String _titleSelectedText = '';
  int? _selectionClearPointerId;
  Offset? _selectionClearPointerDownPosition;
  DateTime? _selectionClearPointerDownTime;
  bool _selectionClearPointerMoved = false;
  static const double _edgeBackSwipeDetectorWidth = 25.0;
  static const double _edgeBackSwipeTriggerWidth = 62.0;
  static const double _edgeBackSwipeMinDistance = 72.0;
  static const double _edgeBackSwipeMinVelocity = 700.0;
  static const bool _webViewScrollOptimizationEnabled = false;
  late final ValueNotifier<double> _backSwipeOffsetNotifier =
      ValueNotifier<double>(0.0);
  late final AnimationController _backSwipeAnimationController;
  Animation<double>? _backSwipeOffsetAnimation;
  bool _popAfterBackSwipeAnimation = false;
  bool _isDraggingBackFromEdge = false;
  bool _didTemporarilyRestorePreviousForSwipe = false;
  int _iosScrollRecoveryKey = IosScrollRecovery.revision;
  double _backDragStartX = 0.0;
  double _backDragDistance = 0.0;

  double get _backSwipeOffset => _backSwipeOffsetNotifier.value;
  set _backSwipeOffset(double value) => _backSwipeOffsetNotifier.value = value;

  @override
  void initState() {
    super.initState();
    _openPostActionService = const OpenPostActionService();
    _postCommentService = PostCommentService();
    DetachableWebViewRouteRegistry.register(this);
    WidgetsBinding.instance.addObserver(this);
    if (_webViewScrollOptimizationEnabled) {
      SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
    }
    IosScrollRecovery.addListener(_handleIosScrollRecovery);
    _scrollController.addListener(_onScroll);
    _commentController.addListener(_onCommentDraftChanged);
    _commentFocusNode.addListener(_syncCommentComposerExpansion);
    _onCommentDraftChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateKeyboardInset();
    });
    _backSwipeAnimationController = AnimationController(vsync: this)
      ..addListener(_onBackSwipeAnimationTick)
      ..addStatusListener(_onBackSwipeAnimationStatusChanged);

    Future.wait([
      _loadSfwEnabled(),
      _fetchPostDetails(),
    ]).then((_) {
      if (username != null && !widget.skipInitialWatchCheck) {
        _fetchUserPageLinks();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.unsubscribe(this);
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    DetachableWebViewRouteRegistry.unregister(this);
    routeObserver.unsubscribe(this);
    if (_webViewScrollOptimizationEnabled) {
      SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    }
    IosScrollRecovery.removeListener(_handleIosScrollRecovery);
    _backSwipeAnimationController.dispose();
    _backSwipeOffsetNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _commentController.removeListener(_onCommentDraftChanged);
    _commentController.dispose();
    _commentFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _showScrollToTopNotifier.dispose();
    _keyboardInset.dispose();
    _isCommentComposerExpanded.dispose();
    _isSendingInlineComment.dispose();
    _commentDraftHasText.dispose();
    _commentDraftCollapsedLines.dispose();
    super.dispose();
  }

  void _handleIosScrollRecovery() {
    if (!mounted) return;
    final offset = IosScrollRecovery.currentOffset(_scrollController);
    setState(() {
      _iosScrollRecoveryKey = IosScrollRecovery.revision;
    });
    IosScrollRecovery.restoreOffset(_scrollController, offset);
  }

  @override
  void didPushNext() {
    _dismissCommentComposerFocus();
    if (_suppressNextRouteDetach) {
      return;
    }
    _setRouteWebViewDetached(true);
  }

  @override
  void didPopNext() {
    _setRouteWebViewDetached(false);
    _armCommentComposerFocusGuard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_commentFocusNode.hasFocus) return;
      _commentFocusNode.unfocus();
    });
  }

  @override
  bool get routeWebViewDetached => _isPostWebViewDetached;

  @override
  void setRouteWebViewDetached(bool detached) {
    _setRouteWebViewDetached(detached);
  }

  void _setRouteWebViewDetached(bool detached) {
    if (_isPostWebViewDetached == detached) {
      return;
    }
    _isPostWebViewDetached = detached;
    if (detached) {
      _submissionWebViewKey.currentState?.detachWebView();
    } else {
      _submissionWebViewKey.currentState?.restoreWebView();
    }
    if (mounted) {
      setState(() {});
    }
  }

  List<String> iconBeforeUrls = [];
  List<String> iconAfterUrls = [];

  void _onScroll() {
    if (_webViewScrollOptimizationEnabled) {
      _pauseWebViewDuringScroll();
    }
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 350;
    if (shouldShow == _showScrollToTopNotifier.value) return;
    _showScrollToTopNotifier.value = shouldShow;
  }

  bool _handlePostScrollNotification(ScrollNotification notification) {
    if (_webViewScrollOptimizationEnabled &&
        (notification is ScrollStartNotification ||
            notification is ScrollUpdateNotification ||
            notification is OverscrollNotification)) {
      _pauseWebViewDuringScroll();
    }
    return false;
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    if (!_webViewScrollOptimizationEnabled || _enableScrollWebViewPause) {
      return;
    }
    for (final timing in timings) {
      _frameTimingCount++;
      _frameTimingTotalMicros += timing.totalSpan.inMicroseconds;
    }
    if (_frameTimingCount < 30) {
      return;
    }
    final double averageFrameMicros =
        _frameTimingTotalMicros / _frameTimingCount;
    if (averageFrameMicros > Duration.microsecondsPerSecond / 60) {
      if (mounted) {
        setState(() {
          _enableScrollWebViewPause = true;
        });
      } else {
        _enableScrollWebViewPause = true;
      }
    }
    _frameTimingCount = 0;
    _frameTimingTotalMicros = 0;
  }

  void _pauseWebViewDuringScroll() {
    if (!_webViewScrollOptimizationEnabled || !_enableScrollWebViewPause) {
      return;
    }
    final state = _submissionWebViewKey.currentState;
    if (state == null) {
      return;
    }
    state.pauseWebViewDuringScroll();
  }

  Object _commentSelectionId(Map<String, dynamic> comment, int index) {
    return comment['commentId']?.toString() ?? 'comment_$index';
  }

  GlobalKey<SelectionAreaState> _commentSelectionKeyFor(Object selectionId) {
    return _commentSelectionKeys.putIfAbsent(
      selectionId,
      () => GlobalKey<SelectionAreaState>(),
    );
  }

  String _selectedCommentTextFor(Object selectionId) {
    return _commentSelectedTexts[selectionId] ?? '';
  }

  void _updateTitleSelectedText(SelectedContent? content) {
    _titleSelectedText = content?.plainText ?? '';
  }

  void _updateCommentSelectedText(
    Object selectionId,
    SelectedContent? content,
  ) {
    final text = content?.plainText ?? '';
    if (text.isEmpty) {
      _commentSelectedTexts.remove(selectionId);
      return;
    }
    _commentSelectedTexts[selectionId] = text;
  }

  bool _shouldOfferPostTranslation(
    TranslatorSettingsProvider settings, {
    VoidCallback? onLanguageDetectionUpdated,
  }) {
    return _translationService.shouldOfferTranslation(
      _translationSourceTextBuilder.content(
        title: submissionTitle,
        descriptionHtml: submissionDescription,
      ),
      settings,
      onLanguageDetectionUpdated: onLanguageDetectionUpdated,
    );
  }

  bool _shouldOfferCommentTranslation(
    Map<String, dynamic> comment,
    TranslatorSettingsProvider settings, {
    VoidCallback? onLanguageDetectionUpdated,
  }) {
    if (!_translationSourceTextBuilder.isCommentAvailable(comment)) {
      return false;
    }
    return _translationService.shouldOfferTranslation(
      _translationSourceTextBuilder.comment(comment),
      settings,
      onLanguageDetectionUpdated: onLanguageDetectionUpdated,
    );
  }

  Future<void> _openPostTranslation(
    TranslatorSettingsProvider settings,
  ) async {
    await NativeTranslateLauncher.open(
      _translationSourceTextBuilder.content(
        title: submissionTitle,
        descriptionHtml: submissionDescription,
      ),
      targetLanguageCode: settings.targetLanguageCode,
    );
  }

  Future<void> _openCommentTranslation(
    Map<String, dynamic> comment,
    TranslatorSettingsProvider settings,
  ) async {
    await NativeTranslateLauncher.open(
      _translationSourceTextBuilder.comment(comment),
      targetLanguageCode: settings.targetLanguageCode,
    );
  }

  void _handleTranslationLanguageDetected() {
    if (!mounted) return;
    setState(() {});
  }

  void _clearSelectionArea(GlobalKey<SelectionAreaState> key) {
    final state = key.currentState;
    if (state == null) return;
    state.selectableRegion.clearSelection();
    state.selectableRegion.hideToolbar();
  }

  void _clearAllTextSelections() {
    _clearSelectionArea(_titleSelectionKey);
    for (final key in _commentSelectionKeys.values) {
      _clearSelectionArea(key);
    }
  }

  void _handleSelectionClearPointerDown(PointerDownEvent event) {
    _selectionClearPointerId = event.pointer;
    _selectionClearPointerDownPosition = event.position;
    _selectionClearPointerDownTime = DateTime.now();
    _selectionClearPointerMoved = false;
  }

  void _handleSelectionClearPointerMove(PointerMoveEvent event) {
    if (_selectionClearPointerId != event.pointer ||
        _selectionClearPointerDownPosition == null) {
      return;
    }
    if ((event.position - _selectionClearPointerDownPosition!).distance > 10) {
      _selectionClearPointerMoved = true;
    }
  }

  void _handleSelectionClearPointerUp(PointerUpEvent event) {
    if (_selectionClearPointerId != event.pointer) return;
    final downTime = _selectionClearPointerDownTime;
    final isQuickTap = downTime != null &&
        DateTime.now().difference(downTime) <=
            const Duration(milliseconds: 250);
    if (!_selectionClearPointerMoved && isQuickTap) {
      _clearAllTextSelections();
    }
    _resetSelectionClearPointer();
  }

  void _handleSelectionClearPointerCancel(PointerCancelEvent event) {
    if (_selectionClearPointerId != event.pointer) return;
    _resetSelectionClearPointer();
  }

  void _resetSelectionClearPointer() {
    _selectionClearPointerId = null;
    _selectionClearPointerDownPosition = null;
    _selectionClearPointerDownTime = null;
    _selectionClearPointerMoved = false;
  }

  @override
  void didChangeMetrics() {
    _updateKeyboardInset();
  }

  void _updateKeyboardInset() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;

    final view = views.first;

    final previousInset = _keyboardInset.value;
    final inset = view.viewInsets.bottom / view.devicePixelRatio;

    if ((inset - previousInset).abs() > 0.5) {
      _keyboardInset.value = inset;

      final keyboardJustClosed = previousInset > 0 && inset <= 0.5;
      if (keyboardJustClosed && _commentFocusNode.hasFocus) {
        _commentFocusNode.unfocus();
      }
    }
  }

  Future<void> _loadSfwEnabled() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    setState(() {
      _sfwEnabled = sfwEnabled;
    });
  }

  Future<Response> _getWithSfwCookie(
    String url, {
    Map<String, String>? additionalHeaders,
    bool skipSfw = false,
  }) async {
    final response = await _openPostCookieService.getWithSfwCookie(
      url: url,
      sfwEnabled: _sfwEnabled,
      nsfwAllowed: _nsfwAllowed,
      additionalHeaders: additionalHeaders,
      skipSfw: skipSfw,
    );

    debugPrint('Response status: ${response.statusCode}');

    final ct = (response.headers['content-type'] ?? '').toLowerCase();
    if (response.statusCode == 200 &&
        (ct.contains('text/html') || ct.contains('application/xhtml'))) {
      final decodedBody = decodeOpenPostResponseBody(response.bodyBytes);

      if (hasSubmissionNotFoundError(decodedBody)) {
        debugPrint('DETECTED: Submission not found error');
        throw Exception("Submission not found in database");
      }

      if (!skipSfw) {
        if (hasMatureContentWarning(decodedBody) && !_nsfwAllowed) {
          debugPrint('DETECTED: Mature/Adult content warning - showing dialog');

          final userAgreed = await _showNSFWConfirmationDialog();
          debugPrint('User response: $userAgreed');

          if (userAgreed) {
            setState(() => _nsfwAllowed = true);
            debugPrint('Retrying request with NSFW allowed');
            final retryResponse = await _getWithSfwCookie(
              url,
              additionalHeaders: additionalHeaders,
              skipSfw: true,
            );
            debugPrint('Retry response status: ${retryResponse.statusCode}');
            return retryResponse;
          } else {
            debugPrint('User declined NSFW content');
            throw Exception("User declined to view NSFW content.");
          }
        }

        if (hasOldMatureImageError(decodedBody) && !_nsfwAllowed) {
          debugPrint('DETECTED: Old style mature error - showing dialog');
          final userAgreed = await _showNSFWConfirmationDialog();
          if (userAgreed) {
            setState(() => _nsfwAllowed = true);
            return await _getWithSfwCookie(
              url,
              additionalHeaders: additionalHeaders,
              skipSfw: true,
            );
          } else {
            throw Exception("User declined to view NSFW content.");
          }
        }
      }
    }

    return response;
  }

  Future<bool> _showNSFWConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('NSFW Content'),
              content: const Text(
                  'This post is marked NSFW. Are you sure you want to view it?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black,
                  ),
                  child:
                      const Text('No', style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black,
                  ),
                  child: const Text('Yes', style: TextStyle(color: Colors.red)),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _fetchUserPageLinks() async {
    if (username == null) return;

    final result = await const OpenPostUserActionsLoader().load(
      url: buildOpenPostUserUrl(username!),
      fetch: _getWithSfwCookie,
    );

    if (result.actions != null) {
      final actions = result.actions!;

      setState(() {
        watchLink = actions.watchLink;
        unwatchLink = actions.unwatchLink;
        blockLink = actions.blockLink;
        unblockLink = actions.unblockLink;
        _blockKey = actions.blockKey;
        _unblockKey = actions.unblockKey;
        _isClassicUserPage = actions.isClassic;

        isWatching = actions.isWatching;
        isBlocked = actions.isBlocked;
      });
    } else {
      debugPrint('Failed to fetch user page links: ${result.statusCode}');
    }
  }

  Widget _buildTagsPanel() {
    final bool hasAnyTags =
        keywordTags.isNotEmpty || metaKeywordTags.isNotEmpty;

    // Guard: some posts have *only* meta keywords. In that case, older parsing
    // fallbacks could end up treating the meta section as normal keywords,
    // making the UI show the same chips twice. If both groups are identical,
    // show only the meta group.
    final Set<String> keywordSet =
        keywordTags.map((t) => t.name.toLowerCase()).toSet();
    final Set<String> metaSet =
        metaKeywordTags.map((t) => t.name.toLowerCase()).toSet();
    final bool hideKeywordGroup = keywordSet.isNotEmpty &&
        metaSet.isNotEmpty &&
        keywordSet.length == metaSet.length &&
        keywordSet.containsAll(metaSet);

    if (!hasAnyTags) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Text(
          'No keywords available.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding:
          EdgeInsets.fromLTRB(12, 10, 12, metaKeywordTags.isNotEmpty ? 4 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (keywordTags.isNotEmpty && !hideKeywordGroup)
            _buildTagsGroup(
                title: 'Keywords', tags: keywordTags, allowSearch: true),
          if (metaKeywordTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildTagsGroup(
                title: 'Meta Keywords',
                tags: metaKeywordTags,
                allowSearch: false),
          ],
        ],
      ),
    );
  }

  Widget _buildTagsGroup({
    required String title,
    required List<FaPostTag> tags,
    required bool allowSearch,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          spacing: 10,
          runSpacing: 10,
          children: tags
              .map((t) => _buildTagPill(t, allowSearch: allowSearch))
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildTagPill(FaPostTag tag, {required bool allowSearch}) {
    final bool inFlight = _tagToggleInFlight.contains(tag.name);
    final bool isBlocked = tag.isBlocked;

    final Color accent = isBlocked ? Colors.redAccent : const Color(0xFFE09321);
    final Color border =
        isBlocked ? accent.withValues(alpha: 0.55) : const Color(0xFF2A2A2A);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: isBlocked
                ? 'Click to remove this tag from the blocklist!'
                : 'Click to add this tag to the blocklist!',
            child: InkWell(
              onTap: inFlight ? null : () => _toggleTagBlock(tag),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: inFlight
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : Icon(
                          isBlocked ? Icons.remove : Icons.add,
                          size: 16,
                          color: Colors.black,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: (allowSearch && tag.isSearchable)
                ? () => _navigateToSearch(tag.name)
                : null,
            child: Text(
              tag.name,
              style: TextStyle(
                fontSize: 13,
                color: (allowSearch && tag.isSearchable)
                    ? Colors.white
                    : Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTagBlock(FaPostTag tag) async {
    if (_tagToggleInFlight.contains(tag.name)) return;

    if (tagBlocklistNonce == null || tagBlocklistNonce!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Tag blocking is unavailable right now (missing nonce).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _tagToggleInFlight.add(tag.name));

    try {
      final shouldBlock = !tag.isBlocked;
      await _sendTagBlocklistRequest(tag.name, shouldBlock: shouldBlock);

      // Update UI immediately so +/− changes without waiting for a full refresh.
      _applyLocalTagBlockState(tag.name, isBlocked: shouldBlock);

      // Refresh so the block/unblock state and blocked-content markers match FA.
      await _fetchPostDetails();

      // If the refreshed HTML didn't reflect the change yet, keep UI consistent.
      _applyLocalTagBlockState(tag.name, isBlocked: shouldBlock);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shouldBlock
                ? 'Tag blocked: ${tag.name}'
                : 'Tag unblocked: ${tag.name}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed to ${tag.isBlocked ? 'unblock' : 'block'} tag: ${tag.name}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _tagToggleInFlight.remove(tag.name));
    }
  }

  void _applyLocalTagBlockState(String tagName, {required bool isBlocked}) {
    final result = updateOpenPostTagBlockState(
      keywordTags: keywordTags,
      metaKeywordTags: metaKeywordTags,
      tagName: tagName,
      isBlocked: isBlocked,
    );
    if (!result.updated) return;
    setState(() {
      keywordTags = result.keywordTags;
      metaKeywordTags = result.metaKeywordTags;
    });
  }

  Future<void> _sendTagBlocklistRequest(String tagName,
      {required bool shouldBlock}) async {
    if (tagBlocklistNonce == null || tagBlocklistNonce!.isEmpty) {
      throw Exception('Missing tag blocklist nonce.');
    }

    final result = await _openPostActionService.performTagBlocklistRequest(
      tagName: tagName,
      shouldBlock: shouldBlock,
      nonce: tagBlocklistNonce!,
      submissionId: widget.uniqueNumber,
      sfwEnabled: _sfwEnabled,
    );

    if (result.status == OpenPostActionStatus.missingAuth) {
      throw Exception('Not logged in.');
    }

    if (result.status != OpenPostActionStatus.success) {
      throw Exception('Tag blocklist request failed: ${result.statusCode}');
    }
  }

  void _navigateToSearch(String keyword) {
    String formattedKeyword = '@keywords $keyword';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            KeywordSearchScreen(initialKeyword: formattedKeyword),
      ),
    );
  }

  Future<void> _handleBlockUnblock() async {
    // When we skipped initial fetch, load links on first use (same as Watch)
    if (blockLink == null && unblockLink == null && username != null) {
      setState(() => _watchLinksLoading = true);
      await _fetchUserPageLinks();
      if (!mounted) return;
      setState(() => _watchLinksLoading = false);
    }
    if (isBlocked) {
      if (unblockLink == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot unblock author at this time.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final key = extractOpenPostActionKey(unblockLink!, _unblockKey);
      if (key == null || key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unblock key is missing.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await _sendBlockUnblockPostRequest('/unblock/$linkUsername/', key,
          shouldBlock: false);
    } else {
      if (blockLink == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot block author at this time.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final key = extractOpenPostActionKey(blockLink!, _blockKey);
      if (key == null || key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Block key is missing.'),
            backgroundColor: Colors.red,
          ),
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
      final result = await _openPostActionService.performBlockUnblockRequest(
        urlPath: urlPath,
        keyValue: keyValue,
        linkUsername: linkUsername ?? '',
        sfwEnabled: _sfwEnabled,
      );

      if (result.status == OpenPostActionStatus.missingAuth) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to perform this action.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (result.status == OpenPostActionStatus.success) {
        await _fetchUserPageLinks();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${shouldBlock ? 'Author blocked' : 'Author unblocked'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to ${shouldBlock ? 'block' : 'unblock'} author.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'An error occurred while trying to ${shouldBlock ? 'block' : 'unblock'} author.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendWatchUnwatchRequest(String urlPath,
      {required bool shouldWatch}) async {
    final fullUrl = buildOpenPostAbsolutePath(urlPath);
    try {
      final result = await _openPostActionService.performAuthenticatedGet(
        url: fullUrl,
        sfwEnabled: _sfwEnabled,
      );
      if (result.status == OpenPostActionStatus.missingAuth) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to perform this action.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (result.status == OpenPostActionStatus.success) {
        await _fetchUserPageLinks();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${shouldWatch ? 'Now watching $username' : 'Stopped watching $username'}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleWatchButtonPressed() async {
    // When we skipped initial fetch (Browse/Search), fetch links on first tap
    if (watchLink == null && unwatchLink == null && username != null) {
      if (_watchLinksLoading) return;
      setState(() => _watchLinksLoading = true);
      await _fetchUserPageLinks();
      if (!mounted) return;
      setState(() => _watchLinksLoading = false);
      // After fetch: if already watching, button will show -Watch; else send watch request below
    }
    if (isWatching) {
      if (unwatchLink == null) return;
      await _sendWatchUnwatchRequest(unwatchLink!, shouldWatch: false);
    } else {
      if (watchLink == null) return;
      await _sendWatchUnwatchRequest(watchLink!, shouldWatch: true);
    }
  }

  Future<void> hideComment(String hideLink, String commentId) async {
    final shouldHide = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmation"),
          content: const Text(
            "Are you sure you want to hide this comment?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Yes"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );

    if (shouldHide == true) {
      try {
        final statusCode = await _openPostActionService.sendAuthenticatedGet(
          url: hideLink,
          sfwEnabled: _sfwEnabled,
        );
        if (statusCode == null) return;
        if (statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Comment successfully hidden!"),
              backgroundColor: Colors.green,
            ),
          );
          await _fetchPostDetails();
        } else {
          debugPrint('Failed to hide comment. Status code: $statusCode');
        }
      } catch (e) {
        debugPrint('Error hiding comment: $e');
      }
    }
  }

  Future<void> _fetchFavoriteLinks() async {
    final result = await OpenPostFavoriteLinksLoader(
      cookieService: _openPostCookieService,
    ).load(
      url: buildSubmissionViewUrl(widget.uniqueNumber),
      fetch: _getWithSfwCookie,
    );

    if (result.status == OpenPostFavoriteLinksLoadStatus.success) {
      setState(() {
        favLink = result.favoriteLink;
        unfavLink = result.unfavoriteLink;
        isFavorited = result.isFavorited;
      });
    } else if (result.status == OpenPostFavoriteLinksLoadStatus.httpFailure) {
      debugPrint('Failed to fetch favorite links: ${result.statusCode}');
    }
  }

  Future<void> _fetchPostDetails() async {
    setState(() => isLoading = true);

    if (!await _openPostCookieService.hasAuthCookies()) {
      setState(() => isLoading = false);
      return;
    }

    final postUrl = buildSubmissionViewUrl(widget.uniqueNumber);

    try {
      final result = await const OpenPostDetailsLoader().load(
        url: postUrl,
        fetch: _getWithSfwCookie,
      );

      if (result.status == OpenPostDetailsLoadStatus.httpFailure) {
        debugPrint('Failed to fetch post details: ${result.statusCode}');
        setState(() => isLoading = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load submission'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      if (result.status == OpenPostDetailsLoadStatus.matureWarning) {
        debugPrint(
            'ERROR: Still got mature warning after retry - this should not happen');
        setState(() => isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load NSFW content'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      final parsedPost = result.parsedPost!;
      final parsedComments = result.comments!;

      setState(() {
        currentUsername = parsedPost.currentUsername;
        username = parsedPost.username;
        linkUsername = parsedPost.linkUsername;
        profileImageUrl = parsedPost.profileImageUrl;
        submissionTitle = parsedPost.submissionTitle;
        fullViewImageUrl = parsedPost.fullViewImageUrl;
        submissionDescription = parsedPost.submissionDescription;
        rating = parsedPost.rating;

        if (parsedPost.publicationTimeRaw != null &&
            parsedPost.publicationTimeRaw!.isNotEmpty) {
          _parsePublicationTime(parsedPost.publicationTimeRaw!);
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
        _detailsLoaded = true;
        isLoading = false;
      });

      debugPrint('Post loaded successfully: $submissionTitle');
    } catch (e) {
      debugPrint('Error fetching post details: $e');
      setState(() => isLoading = false);

      if (mounted) {
        String errorMessage = 'Failed to load submission';

        if (e.toString().contains('not found in database')) {
          errorMessage = 'This submission does not exist or has been deleted';
        } else if (e.toString().contains('declined to view NSFW')) {
          errorMessage = 'NSFW content viewing declined';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );

        // Navigate back after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    }
  }

  Future<void> _handleDeletePost() async {
    try {
      final result = await _openPostActionService.prepareDeletion(
        submissionId: widget.uniqueNumber,
      );

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to perform this action.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (result.statusCode == 200) {
        final confirmationData = result.confirmationData;
        if (confirmationData == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to prepare deletion.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        _showDeleteConfirmationDialog(confirmationData);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initiate deletion.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error initiating deletion: $e');
      debugPrint('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An unexpected error occurred.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDeleteConfirmationDialog(
    OpenPostDeleteConfirmationData confirmationData,
  ) {
    final TextEditingController passwordController = TextEditingController();
    final FocusNode passwordFocusNode = FocusNode();

    void submitDeletion(BuildContext dialogContext) {
      final String password = passwordController.text;
      if (password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password cannot be empty.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      TextInput.finishAutofillContext(shouldSave: true);
      Navigator.of(dialogContext).pop();
      _confirmDeletion(confirmationData, password);
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: AutofillGroup(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'The following submission is going to be removed from your gallery:',
                  ),
                  const SizedBox(height: 8),
                  if (fullViewImageUrl != null)
                    FaNetworkImage(
                      fullViewImageUrl!,
                      height: 150,
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'This procedure is irreversible.\n\nPlease enter your account password below as a confirmation.',
                  ),
                  const SizedBox(height: 8),
                  // Hidden username field so Android autofill recognises a credential pair
                  if (currentUsername != null)
                    SizedBox(
                      height: 0,
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          autofillHints: const [AutofillHints.username],
                          controller:
                              TextEditingController(text: currentUsername),
                          readOnly: true,
                          enableInteractiveSelection: false,
                          focusNode: _AlwaysDisabledFocusNode(),
                        ),
                      ),
                    ),
                  TextField(
                    controller: passwordController,
                    focusNode: passwordFocusNode,
                    obscureText: true,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                    ),
                    onSubmitted: (_) => submitDeletion(dialogContext),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                TextInput.finishAutofillContext(shouldSave: false);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () => submitDeletion(dialogContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Confirm Deletion'),
            ),
          ],
        );
      },
    ).then((_) {
      passwordController.dispose();
      passwordFocusNode.dispose();
    });
  }

  Future<void> _confirmDeletion(
    OpenPostDeleteConfirmationData confirmationData,
    String password,
  ) async {
    try {
      final success = await _openPostActionService.confirmDeletion(
        confirmValue: confirmationData.confirmValue,
        deleteSubmissionsSubmitValue:
            confirmationData.deleteSubmissionsSubmitValue,
        submissionIdValue: confirmationData.submissionIdValue,
        password: password,
      );

      if (success == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to perform this action.'),
            backgroundColor: Colors.red,
          ),
        );
      } else if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Submission deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete submission.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An error occurred while deleting the submission.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showInfoDialog() {
    _dismissCommentComposerFocus();
    _suppressNextRouteDetach = true;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Post Information'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category != null)
                  Text(
                    'Category: $category',
                    style: const TextStyle(fontSize: 16),
                  ),
                if (category != null) const SizedBox(height: 8),
                if (type != null)
                  Text(
                    'Sub-Category: $type',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 8),
                if (species != null)
                  Text(
                    'Species: $species',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 8),
                if (gender != null)
                  Text(
                    'Gender: $gender',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 8),
                if (size != null)
                  Text(
                    'Size: $size',
                    style: const TextStyle(fontSize: 16),
                  ),
                const SizedBox(height: 8),
                if (fileSize != null)
                  Text(
                    'File Size: $fileSize',
                    style: const TextStyle(fontSize: 16),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      _suppressNextRouteDetach = false;
    });
  }

  Future<void> _openImageInspectScreen(String imageUrl) async {
    _dismissCommentComposerFocus();
    _suppressNextRouteDetach = true;
    try {
      await Navigator.push(
        context,
        ImageInspectScreen.route(imageUrl: imageUrl),
      );
    } finally {
      _suppressNextRouteDetach = false;
    }
  }

  void _parsePublicationTime(String rawTime) {
    try {
      final parsed = parseSubmissionPublicationTime(
        rawTime,
        applyDstCorrection: isDstCorrectionApplied,
      );
      if (parsed != null) {
        publicationTime = parsed;
        debugPrint("Successfully parsed FA date: $publicationTime");
        return;
      }

      debugPrint(
          "Could not parse date with any format. Raw string: '$rawTime'");
    } catch (e, stackTrace) {
      debugPrint("Error parsing publication time: $e");
      debugPrint("Raw time string was: '$rawTime'");
      debugPrint("Stack trace: $stackTrace");
    }
  }

  String? getFormattedPublicationTime() {
    if (publicationTime == null) return null;
    final localTime = publicationTime!.toLocal();
    return DateFormat.yMMMd().add_jm().format(localTime);
  }

  void _sharePost() {
    final postUrl = buildSubmissionViewUrl(widget.uniqueNumber);
    final shareContent = '$postUrl';
    const FaShareService().shareText(
      text: shareContent,
      subject: submissionTitle ?? 'Fur Affinity Post',
    );
  }

  void _addComment(String commentText) {
    setState(() {
      comments.add({
        'profileImage': null,
        'username': 'You',
        'text': commentText,
        'width': 100.0,
        'isOP': false,
      });
      commentsCount = (commentsCount) + 1;
    });
  }

  void _syncCommentComposerExpansion() {
    final shouldExpand = _commentFocusNode.hasFocus;
    if (shouldExpand &&
        _blockRestoredCommentComposerFocus &&
        !_commentComposerFocusRequestedByUser) {
      _dismissCommentComposerFocus();
      return;
    }
    if (shouldExpand != _isCommentComposerExpanded.value) {
      _isCommentComposerExpanded.value = shouldExpand;
    }
    if (shouldExpand) {
      _commentComposerFocusRequestedByUser = false;
      _blockRestoredCommentComposerFocus = false;
    } else {
      _commentComposerFocusRequestedByUser = false;
      _blockRestoredCommentComposerFocus = true;
    }
  }

  void _armCommentComposerFocusGuard() {
    _commentComposerFocusRequestedByUser = false;
    _blockRestoredCommentComposerFocus = true;
  }

  void _allowCommentComposerFocusFromUser() {
    _commentComposerFocusRequestedByUser = true;
    _blockRestoredCommentComposerFocus = false;
  }

  void _handleCommentComposerPointerDown(PointerDownEvent event) {
    _allowCommentComposerFocusFromUser();
  }

  void _dismissCommentComposerFocus() {
    _armCommentComposerFocusGuard();
    if (_commentFocusNode.hasFocus) {
      _commentFocusNode.unfocus();
    }
  }

  void _onCommentDraftChanged() {
    final bool hasText = _commentController.text.trim().isNotEmpty;
    if (hasText != _commentDraftHasText.value) {
      _commentDraftHasText.value = hasText;
    }

    final int collapsedLines = collapsedComposerLines(_commentController.text);
    if (collapsedLines != _commentDraftCollapsedLines.value) {
      _commentDraftCollapsedLines.value = collapsedLines;
    }
  }

  Future<void> _sendInlineComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty || _isSendingInlineComment.value) return;
    _isSendingInlineComment.value = true;

    try {
      final success = await _postCommentService.submitComment(
        message: commentText,
        submissionId: widget.uniqueNumber,
      );

      if (!mounted) return;

      if (success) {
        _addComment(commentText);
        _commentController.clear();
        _commentFocusNode.unfocus();
        await _fetchPostDetails();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment posted!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error posting comment. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        _isSendingInlineComment.value = false;
      }
    }
  }

  Widget _buildComposerSendButton({
    required bool canSend,
    required bool isSending,
    bool compact = false,
  }) {
    final buttonSize = compact ? 30.0 : 40.0;

    if (isSending) {
      return SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton(
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: buttonSize,
        height: buttonSize,
      ),
      visualDensity: VisualDensity.compact,
      icon: Icon(
        Icons.send,
        color: canSend ? const Color(0xFFE09321) : Colors.white54,
      ),
      onPressed: canSend ? _sendInlineComment : null,
    );
  }

  Future<void> _unhideComment(String unhideLink, String commentId) async {
    final shouldUnhide = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmation"),
          content: const Text("Are you sure you want to unhide this comment?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Yes"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );

    if (shouldUnhide == true) {
      try {
        final statusCode = await _openPostActionService.sendAuthenticatedGet(
          url: unhideLink,
          sfwEnabled: _sfwEnabled,
        );
        if (statusCode == null) return;
        if (statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Comment successfully un-hidden!"),
              backgroundColor: Colors.green,
            ),
          );
          await _fetchPostDetails();
        } else {
          debugPrint('Failed to unhide comment. Status code: $statusCode');
        }
      } catch (e) {
        debugPrint('Error un-hiding comment: $e');
      }
    }
  }

  /// Downloads the image from [imageUrl] and saves it to the gallery.
  Future<void> _downloadImage(BuildContext context, String imageUrl) async {
    try {
      final result =
          await _openPostMediaExportService.exportToGallery(imageUrl);
      if (result.status == OpenPostMediaExportStatus.permissionDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo permission denied'),
            backgroundColor: Colors.red,
          ),
        );
      } else if (result.status == OpenPostMediaExportStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image saved to gallery!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save image to gallery.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Shares the image from [imageUrl] using the device's share menu.
  /// Downloads the image, writes it to a temporary file, then triggers sharing.
  Future<void> _shareImage(BuildContext context, String imageUrl) async {
    try {
      final result = await _openPostMediaExportService.shareFromUrl(imageUrl);
      if (result.status == OpenPostMediaExportStatus.permissionDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String fixTruncatedLinks(String htmlContent) {
    return replaceTruncatedSubmissionLinks(htmlContent);
  }

  /// Returns the full URL from a truncated comment link.
  String? _getFullLinkFromCommentHtml(String commentHtml, String truncatedUrl) {
    return findFullShortenedCommentLink(commentHtml, truncatedUrl);
  }

  String _getFullLinkFromCommentSource(String truncatedUrl,
      {String? htmlSource}) {
    if (htmlSource == null) return truncatedUrl;
    return _getFullLinkFromCommentHtml(htmlSource, truncatedUrl) ??
        truncatedUrl;
  }

  /// Handles FA links found in comments.
  Future<void> _handleCommentLink(
      BuildContext context, String url, String commentHtml) async {
    final fullUrl = url.contains(".....")
        ? _getFullLinkFromCommentSource(url, htmlSource: commentHtml)
        : url;
    final target = matchFALink(fullUrl);

    switch (target.type) {
      case FALinkTargetType.gallery:
        Navigator.push(
          context,
          UserProfileScreen.route(
            nickname: target.username!,
            initialSection: ProfileSection.Gallery,
          ),
        );
        return;
      case FALinkTargetType.galleryFolder:
        final tappedUsername = target.username!;
        final folderNumber = target.folderNumber!;
        final folderName = target.folderName!;
        final folderUrl = buildFAGalleryFolderUrl(
          username: tappedUsername,
          folderNumber: folderNumber,
          folderName: folderName,
        );
        Navigator.push(
          context,
          UserProfileScreen.route(
            nickname: tappedUsername,
            initialSection: ProfileSection.Gallery,
            initialFolderUrl: folderUrl,
            initialFolderName: folderName,
          ),
        );
        return;
      case FALinkTargetType.user:
        Navigator.push(
          context,
          UserProfileScreen.route(nickname: target.username!),
        );
        return;
      case FALinkTargetType.journalUser:
        Navigator.push(
          context,
          UserProfileScreen.route(
            nickname: target.username!,
            initialSection: ProfileSection.Journals,
          ),
        );
        return;
      case FALinkTargetType.journal:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OpenJournal(uniqueNumber: target.journalId!),
          ),
        );
        return;
      case FALinkTargetType.submission:
        Navigator.push(
          context,
          OpenPost.route(
            uniqueNumber: target.submissionId!,
            imageUrl: '',
          ),
        );
        return;
      case FALinkTargetType.external:
        await launchUrlString(fullUrl, mode: LaunchMode.externalApplication);
        return;
    }
  }

  void _showEditDialog() {
    _dismissCommentComposerFocus();
    _suppressNextRouteDetach = true;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Submission'),
          content: const Text('What do you want to do?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _suppressNextRouteDetach = false;
                _openSubmissionEdit('info');
              },
              child: const Text('Edit Submission Info'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _suppressNextRouteDetach = false;
                _openSubmissionEdit('file');
              },
              child: const Text('Update Source File'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      _suppressNextRouteDetach = false;
    });
  }

  void _openSubmissionEdit(String type) {
    String editUrl;
    if (type == 'info') {
      editUrl = buildOpenPostChangeInfoUrl(widget.uniqueNumber);
    } else {
      editUrl = buildOpenPostChangeSubmissionUrl(widget.uniqueNumber);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSubmissionScreen(initialUrl: editUrl),
      ),
    ).then((_) {
      _fetchPostDetails();
    });
  }

  Future<bool> _confirmClosePostIfNeeded() async {
    if (_commentController.text.trim().isEmpty) {
      return true;
    }

    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Discard draft?'),
          content: const Text('Are you sure you want to close this post?'),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: Size.zero,
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: Size.zero,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Close', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    return shouldClose ?? false;
  }

  Future<bool> _closePost({
    bool resetBackSwipeOffset = true,
  }) async {
    final canClose = await _confirmClosePostIfNeeded();
    if (!canClose || !mounted) return false;

    _setRouteWebViewDetached(true);
    if (resetBackSwipeOffset) {
      _resetEdgeBackSwipe();
    }

    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (!mounted) {
      return false;
    }
    Navigator.pop(context);
    return true;
  }

  Future<void> _sendFavoriteRequest(bool shouldFavorite) async {
    String? url;
    if (shouldFavorite) {
      if (favLink != null) {
        url = buildOpenPostAbsolutePath(favLink!);
      } else {
        return;
      }
    } else {
      if (unfavLink != null) {
        url = buildOpenPostAbsolutePath(unfavLink!);
      } else {
        return;
      }
    }

    try {
      final statusCode = await _openPostActionService.sendAuthenticatedGet(
        url: url,
        sfwEnabled: _sfwEnabled,
      );
      if (statusCode == null) return;
      if (statusCode == 200) {
        await _fetchFavoriteLinks();
      } else {
        debugPrint('Failed to toggle favorite: $statusCode');
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
    }
  }

  Future<bool> _toggleFavorite(bool isLiked) async {
    String normalizedCurrent =
        normalizeFAUsernameForComparison(currentUsername);
    String normalizedPost = normalizeFAUsernameForComparison(username);

    if (normalizedCurrent == normalizedPost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You cannot favorite your own post."),
          backgroundColor: Colors.red,
        ),
      );
      return isLiked;
    }

    bool newLikeState = !isLiked;
    setState(() {
      isFavorited = newLikeState;
      favoritesCount += newLikeState ? 1 : -1;
    });

    _pendingFavoriteState = newLikeState;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      await _sendFavoriteRequest(_pendingFavoriteState);
    });

    return newLikeState;
  }

  void _onBackSwipeAnimationTick() {
    final animation = _backSwipeOffsetAnimation;
    if (animation == null) {
      return;
    }
    _backSwipeOffset = animation.value;
  }

  void _onBackSwipeAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }

    final shouldPop = _popAfterBackSwipeAnimation;
    _backSwipeOffsetAnimation = null;
    _popAfterBackSwipeAnimation = false;

    if (shouldPop) {
      _finishBackSwipeClose();
    }
  }

  Future<void> _finishBackSwipeClose() async {
    final didPop = await _closePost(resetBackSwipeOffset: false);
    if (!didPop && mounted) {
      _detachPreviousRouteWebViewAfterCanceledSwipe();
      _animateBackSwipeTo(
        0.0,
        duration: const Duration(milliseconds: 180),
      );
    }
  }

  Duration _backSwipeCloseDuration(
    double screenWidth,
    double velocity,
  ) {
    final remaining = max(0.0, screenWidth - _backSwipeOffset);
    if (remaining <= 0.0) {
      return Duration.zero;
    }

    if (velocity > 0.0) {
      final milliseconds =
          ((remaining / velocity) * 1000).round().clamp(90, 240);
      return Duration(milliseconds: milliseconds);
    }

    final distanceFactor = (remaining / screenWidth).clamp(0.2, 1.0);
    return Duration(milliseconds: (220 * distanceFactor).round());
  }

  Duration _backSwipeResetDuration(double screenWidth) {
    if (screenWidth <= 0.0) {
      return const Duration(milliseconds: 180);
    }

    final distanceFactor = (_backSwipeOffset / screenWidth).clamp(0.15, 1.0);
    return Duration(milliseconds: (180 * distanceFactor).round());
  }

  void _animateBackSwipeTo(
    double target, {
    required Duration duration,
    Curve curve = Curves.easeOutCubic,
    bool popWhenDone = false,
  }) {
    _backSwipeAnimationController.stop();
    _backSwipeAnimationController.duration = duration;
    _backSwipeOffsetAnimation = Tween<double>(
      begin: _backSwipeOffset,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _backSwipeAnimationController,
        curve: curve,
      ),
    );
    _popAfterBackSwipeAnimation = popWhenDone;
    _backSwipeAnimationController.forward(from: 0.0);
  }

  void _handleEdgeBackSwipePointerDown(PointerDownEvent event) {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    if (event.position.dx <= _edgeBackSwipeTriggerWidth) {
      _restorePreviousRouteWebViewForSwipe();
    }
  }

  void _handleEdgeBackSwipePointerUp(PointerEvent event) {
    if (!_isDraggingBackFromEdge && _backSwipeOffset == 0.0) {
      _detachPreviousRouteWebViewAfterCanceledSwipe();
    }
  }

  void _handleEdgeBackSwipeStart(DragStartDetails details) {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    if (details.globalPosition.dx <= _edgeBackSwipeTriggerWidth) {
      _backSwipeAnimationController.stop();
      _backSwipeOffsetAnimation = null;
      _popAfterBackSwipeAnimation = false;
      _isDraggingBackFromEdge = true;
      _restorePreviousRouteWebViewForSwipe();
      _backDragStartX = details.globalPosition.dx - _backSwipeOffset;
      _backDragDistance = _backSwipeOffset;
    }
  }

  void _handleEdgeBackSwipeUpdate(DragUpdateDetails details) {
    if (!_isDraggingBackFromEdge) {
      return;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final distance = (details.globalPosition.dx - _backDragStartX)
        .clamp(0.0, screenWidth)
        .toDouble();
    _backDragDistance = distance;
    _backSwipeOffset = distance;
  }

  void _handleEdgeBackSwipeEnd(DragEndDetails details) {
    if (!_isDraggingBackFromEdge) {
      return;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final closeDistanceThreshold =
        max(_edgeBackSwipeMinDistance, screenWidth * 0.25);
    final shouldClose = _backDragDistance >= closeDistanceThreshold ||
        details.velocity.pixelsPerSecond.dx >= _edgeBackSwipeMinVelocity;

    _isDraggingBackFromEdge = false;
    _backDragStartX = 0.0;
    _backDragDistance = 0.0;

    if (shouldClose) {
      _didTemporarilyRestorePreviousForSwipe = false;
      _animateBackSwipeTo(
        screenWidth,
        duration: _backSwipeCloseDuration(
          screenWidth,
          details.velocity.pixelsPerSecond.dx,
        ),
        popWhenDone: true,
      );
    } else {
      _detachPreviousRouteWebViewAfterCanceledSwipe();
      _animateBackSwipeTo(
        0.0,
        duration: _backSwipeResetDuration(screenWidth),
      );
    }
  }

  void _resetEdgeBackSwipe() {
    _isDraggingBackFromEdge = false;
    _backDragStartX = 0.0;
    _backDragDistance = 0.0;
    _backSwipeAnimationController.stop();
    _backSwipeOffsetAnimation = null;
    _popAfterBackSwipeAnimation = false;
    _backSwipeOffset = 0.0;
    _detachPreviousRouteWebViewAfterCanceledSwipe();
  }

  void _restorePreviousRouteWebViewForSwipe() {
    if (_didTemporarilyRestorePreviousForSwipe) {
      return;
    }
    final previous = DetachableWebViewRouteRegistry.previousOf(this);
    if (previous == null) {
      return;
    }
    previous.setRouteWebViewDetached(false);
    _didTemporarilyRestorePreviousForSwipe = true;
  }

  void _detachPreviousRouteWebViewAfterCanceledSwipe() {
    if (!_didTemporarilyRestorePreviousForSwipe) {
      return;
    }
    final previous = DetachableWebViewRouteRegistry.previousOf(this);
    if (previous != null) {
      previous.setRouteWebViewDetached(true);
    }
    _didTemporarilyRestorePreviousForSwipe = false;
  }

  Widget _buildEdgeBackSwipeOverlay() {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: _edgeBackSwipeDetectorWidth,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleEdgeBackSwipePointerDown,
        onPointerUp: _handleEdgeBackSwipePointerUp,
        onPointerCancel: _handleEdgeBackSwipePointerUp,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _handleEdgeBackSwipeStart,
          onHorizontalDragUpdate: _handleEdgeBackSwipeUpdate,
          onHorizontalDragEnd: _handleEdgeBackSwipeEnd,
          onHorizontalDragCancel: _resetEdgeBackSwipe,
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  Widget _buildEdgeBackSwipeTransition({required Widget child}) {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return child;
    }

    return ValueListenableBuilder<double>(
      valueListenable: _backSwipeOffsetNotifier,
      child: child,
      builder: (context, offset, swipeChild) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final progress = screenWidth > 0.0
            ? (offset / screenWidth).clamp(0.0, 1.0).toDouble()
            : 0.0;

        return Transform.translate(
          offset: Offset(offset, 0.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: offset > 0.0
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: 0.24 * (1.0 - (progress * 0.5)),
                        ),
                        blurRadius: 24.0,
                        offset: const Offset(-6.0, 0.0),
                      ),
                    ]
                  : const [],
            ),
            child: swipeChild,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final translatorSettings = context.watch<TranslatorSettingsProvider>();
    final bool showLoadingIndicator = !_detailsLoaded || !_webViewLoaded;
    final double viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
    return ExcludeSemantics(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
          statusBarColor: Color(0xFF111111),
          statusBarIconBrightness: Brightness.light,
        ),
        child: ValueListenableBuilder<bool>(
          valueListenable: _commentDraftHasText,
          builder: (context, hasDraft, child) {
            return PopScope(
              canPop: !hasDraft,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop) {
                  _closePost();
                }
              },
              child: child!,
            );
          },
          child: TickerMode(
            enabled: !_isPostWebViewDetached,
            child: _buildEdgeBackSwipeTransition(
              child: Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.black,
                  scrolledUnderElevation: 0,
                  title: const Text("Post"),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      _closePost();
                    },
                  ),
                  actions: [
                    Builder(
                      builder: (context) {
                        // Build the menu items.
                        List<PopupMenuEntry<String>> menuItems = [
                          const PopupMenuItem<String>(
                            value: 'report',
                            child: Text('Report'),
                          ),
                          if (currentUsername == null ||
                              currentUsername != username)
                            PopupMenuItem<String>(
                              value: 'block_unblock',
                              child: Text(isBlocked
                                  ? 'Unblock author'
                                  : 'Block author'),
                            ),
                          const PopupMenuItem<String>(
                            value: 'info',
                            child: Text('Info'),
                          ),
                          const PopupMenuItem<String>(
                            value: 'copy_link',
                            child: Text('Copy link'),
                          ),
                        ];

                        if (currentUsername != null &&
                            currentUsername == username) {
                          menuItems.add(
                            const PopupMenuItem<String>(
                              value: 'edit',
                              child: Text('Edit'),
                            ),
                          );
                          menuItems.add(
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          );
                        }
                        menuItems.add(
                          const PopupMenuItem<String>(
                            value: 'translate',
                            child: Text('Translate'),
                          ),
                        );

                        return IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () async {
                            _dismissCommentComposerFocus();

                            final RenderBox button =
                                context.findRenderObject() as RenderBox;
                            final RenderBox overlay = Overlay.of(context)
                                .context
                                .findRenderObject() as RenderBox;
                            final RelativeRect position = RelativeRect.fromRect(
                              Rect.fromPoints(
                                button.localToGlobal(
                                    Offset(0, button.size.height),
                                    ancestor: overlay),
                                button.localToGlobal(
                                  button.size.bottomRight(
                                      Offset(0, button.size.height + 10)),
                                  ancestor: overlay,
                                ),
                              ),
                              Offset.zero & overlay.size,
                            );

                            _suppressNextRouteDetach = true;
                            final selected = await showMenu<String>(
                              context: context,
                              position: position,
                              items: menuItems,
                            ).whenComplete(() {
                              _suppressNextRouteDetach = false;
                            });

                            switch (selected) {
                              case 'report':
                                launchUrlString(openPostTroubleTicketsUrl);
                                break;
                              case 'block_unblock':
                                await _handleBlockUnblock();
                                break;
                              case 'info':
                                _showInfoDialog();
                                break;
                              case 'edit':
                                _showEditDialog();
                                break;
                              case 'delete':
                                _handleDeletePost();
                                break;
                              case 'copy_link':
                                final postUrl =
                                    buildSubmissionViewUrl(widget.uniqueNumber);
                                await Clipboard.setData(
                                    ClipboardData(text: postUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Link copied to clipboard'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                break;
                              case 'translate':
                                await _openPostTranslation(translatorSettings);
                                break;
                              default:
                                break;
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
                resizeToAvoidBottomInset: false,
                // Build the main content in a Stack so it can overlay the loading indicator.
                body: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _handleSelectionClearPointerDown,
                  onPointerMove: _handleSelectionClearPointerMove,
                  onPointerUp: _handleSelectionClearPointerUp,
                  onPointerCancel: _handleSelectionClearPointerCancel,
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _handlePostScrollNotification,
                          child: RefreshIndicator(
                            color: const Color(0xFFE09321),
                            backgroundColor: Colors.black,
                            onRefresh: () async {
                              await _fetchPostDetails();
                            },
                            child: CustomScrollView(
                              key: ValueKey<int>(_iosScrollRecoveryKey),
                              controller: _scrollController,
                              physics: Platform.isIOS
                                  ? const AlwaysScrollableScrollPhysics(
                                      parent: BouncingScrollPhysics())
                                  : const AlwaysScrollableScrollPhysics(
                                      parent: ClampingScrollPhysics()),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      if (profileImageUrl != null &&
                                          username != null)
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Flexible(
                                                child: GestureDetector(
                                                  onTap: () {
                                                    Navigator.push(
                                                      context,
                                                      UserProfileScreen.route(
                                                        nickname:
                                                            linkUsername ??
                                                                username!,
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 6.0),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Container(
                                                          width: 36,
                                                          height: 36,
                                                          decoration:
                                                              const BoxDecoration(
                                                            color: Colors
                                                                .transparent,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .zero,
                                                          ),
                                                          child: FaNetworkImage(
                                                            profileImageUrl!,
                                                            fit: BoxFit.cover,
                                                            alignment: Alignment
                                                                .center,

                                                            // Shows while loading (no infinite spinner risk)
                                                            loadingBuilder:
                                                                (context, child,
                                                                    loadingProgress) {
                                                              if (loadingProgress ==
                                                                  null) {
                                                                return child;
                                                              }
                                                              return const Center(
                                                                child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2),
                                                              );
                                                            },

                                                            // Handles errors safely
                                                            errorBuilder:
                                                                (context, error,
                                                                    stackTrace) {
                                                              return Image
                                                                  .asset(
                                                                'assets/images/defaultpic.gif',
                                                                fit: BoxFit
                                                                    .cover,
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 10),
                                                        Flexible(
                                                          child: FittedBox(
                                                            fit: BoxFit
                                                                .scaleDown,
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                ...iconBeforeUrls
                                                                    .map(
                                                                  (url) =>
                                                                      Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        right:
                                                                            4.0),
                                                                    child:
                                                                        FaNetworkImage(
                                                                      url,
                                                                      width: 20,
                                                                      height:
                                                                          20,
                                                                      errorBuilder: (context,
                                                                              error,
                                                                              stackTrace) =>
                                                                          const Icon(
                                                                        Icons
                                                                            .error,
                                                                        size:
                                                                            20,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                Text(
                                                                  username!,
                                                                  style:
                                                                      const TextStyle(
                                                                    fontSize:
                                                                        15,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                                ...iconAfterUrls
                                                                    .map(
                                                                  (url) =>
                                                                      Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                        left:
                                                                            4.0),
                                                                    child:
                                                                        FaNetworkImage(
                                                                      url,
                                                                      width: 20,
                                                                      height:
                                                                          20,
                                                                      errorBuilder: (context,
                                                                              error,
                                                                              stackTrace) =>
                                                                          const Icon(
                                                                        Icons
                                                                            .error,
                                                                        size:
                                                                            20,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (!(currentUsername != null &&
                                                  currentUsername == username))
                                                SizedBox(
                                                  width: 94,
                                                  height: 24,
                                                  child: ElevatedButton(
                                                    onPressed: _watchLinksLoading
                                                        ? null
                                                        : () =>
                                                            _handleWatchButtonPressed(),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          isWatching
                                                              ? Colors.black
                                                              : const Color(
                                                                  0xFFE09321),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(2),
                                                      ),
                                                      side: const BorderSide(
                                                          color: Color(
                                                              0xFFE09321)),
                                                    ),
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: _watchLinksLoading
                                                          ? const SizedBox(
                                                              width: 14,
                                                              height: 14,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            )
                                                          : Text(
                                                              isWatching
                                                                  ? "-Watch"
                                                                  : "+Watch",
                                                              style: TextStyle(
                                                                color: isWatching
                                                                    ? Colors
                                                                        .white
                                                                    : Colors
                                                                        .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      if (fullViewImageUrl != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 0.0),
                                          child: GestureDetector(
                                            onLongPressStart: (details) async {
                                              final tapPosition =
                                                  details.globalPosition;
                                              _suppressNextRouteDetach = true;
                                              final selected =
                                                  await showMenu<String>(
                                                context: context,
                                                position: RelativeRect.fromLTRB(
                                                  tapPosition.dx,
                                                  tapPosition.dy,
                                                  tapPosition.dx,
                                                  tapPosition.dy,
                                                ),
                                                items: [
                                                  const PopupMenuItem(
                                                    value: 'download',
                                                    child: Text('Download'),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'share',
                                                    child: Text('Share image'),
                                                  ),
                                                ],
                                              ).whenComplete(() {
                                                _suppressNextRouteDetach =
                                                    false;
                                              });
                                              if (selected == 'download') {
                                                debugPrint(
                                                    "$fullViewImageUrl image2");
                                                await _downloadImage(
                                                    context, fullViewImageUrl!);
                                              } else if (selected == 'share') {
                                                await _shareImage(
                                                    context, fullViewImageUrl!);
                                              }
                                            },
                                            onTap: () {
                                              _openImageInspectScreen(
                                                  fullViewImageUrl!);
                                            },
                                            child: ClipRect(
                                              child: LayoutBuilder(
                                                builder:
                                                    (context, constraints) {
                                                  final aspectRatio =
                                                      (imageWidth != null &&
                                                              imageHeight !=
                                                                  null)
                                                          ? imageWidth! /
                                                              imageHeight!
                                                          : 16 / 9;
                                                  return AspectRatio(
                                                    aspectRatio: aspectRatio,
                                                    child: FaNetworkImage(
                                                      fullViewImageUrl!,
                                                      fit: BoxFit.contain,
                                                      loadingBuilder: (
                                                        BuildContext context,
                                                        Widget child,
                                                        ImageChunkEvent?
                                                            loadingProgress,
                                                      ) {
                                                        if (loadingProgress ==
                                                            null) {
                                                          return child;
                                                        }
                                                        return Container(
                                                          color: Colors.black,
                                                          child: Center(
                                                            child:
                                                                CircularProgressIndicator(
                                                              value: loadingProgress
                                                                          .expectedTotalBytes !=
                                                                      null
                                                                  ? loadingProgress
                                                                          .cumulativeBytesLoaded /
                                                                      (loadingProgress.expectedTotalBytes ??
                                                                          1)
                                                                  : null,
                                                              valueColor:
                                                                  const AlwaysStoppedAnimation<
                                                                      Color>(
                                                                Color(
                                                                    0xFFE09321),
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                      errorBuilder: (context,
                                                          error, stackTrace) {
                                                        return Container(
                                                          color: Colors.black,
                                                          child: const Center(
                                                            child: Icon(
                                                              Icons
                                                                  .error_outline,
                                                              color:
                                                                  Colors.red,
                                                              size: 40,
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      const Divider(
                                        height: 5.0,
                                        color: Color(0xFF111111),
                                        thickness: 5.0,
                                      ),
                                      const Divider(
                                        height: 3.0,
                                        color: Colors.black,
                                        thickness: 3.0,
                                      ),
                                      const Divider(
                                        height: 3.0,
                                        color: Color(0xFF111111),
                                        thickness: 3.0,
                                      ),
                                      if (submissionTitle != null ||
                                          publicationTime != null)
                                        SelectionArea(
                                          key: _titleSelectionKey,
                                          onSelectionChanged:
                                              _updateTitleSelectedText,
                                          contextMenuBuilder:
                                              ReadOnlySelectionContextMenu
                                                  .builder(
                                            selectedTextProvider: () =>
                                                _titleSelectedText,
                                            includeIosTranslate: true,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (submissionTitle != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 4.0,
                                                          top: 4.0),
                                                  child: Text(
                                                    submissionTitle!,
                                                    style: const TextStyle(
                                                      fontSize: 23,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              if (publicationTime != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 8.0),
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        _showFullPublicationDate =
                                                            !_showFullPublicationDate;
                                                      });
                                                    },
                                                    child: Text(
                                                      '${getFormattedPublicationTime()}',
                                                      style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.grey),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      const Divider(
                                        height: 5.0,
                                        color: Color(0xFF111111),
                                        thickness: 5.0,
                                      ),
                                      const Divider(
                                        height: 2.0,
                                        color: Colors.black,
                                        thickness: 2.0,
                                      ),
                                      const Divider(
                                        height: 3.0,
                                        color: Color(0xFF111111),
                                        thickness: 3.0,
                                      ),
                                      if (submissionDescription != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              right: 16.0,
                                              left: 16.0,
                                              top: 16.0),
                                          child: GestureDetector(
                                            onLongPressStart:
                                                (LongPressStartDetails
                                                    details) async {
                                              final RenderBox overlay =
                                                  Overlay.of(context)
                                                          .context
                                                          .findRenderObject()
                                                      as RenderBox;
                                              final RelativeRect position =
                                                  RelativeRect.fromRect(
                                                details.globalPosition &
                                                    const Size(40, 40),
                                                Offset.zero & overlay.size,
                                              );
                                              _suppressNextRouteDetach = true;
                                              final selected =
                                                  await showMenu<String>(
                                                context: context,
                                                position: position,
                                                items: const [
                                                  PopupMenuItem<String>(
                                                    value: 'copy',
                                                    child: Text('Copy'),
                                                  ),
                                                  PopupMenuItem<String>(
                                                    value: 'select',
                                                    child: Text('Select Text'),
                                                  ),
                                                ],
                                              ).whenComplete(() {
                                                _suppressNextRouteDetach =
                                                    false;
                                              });
                                              if (selected == 'copy') {
                                                String? plainText =
                                                    await _submissionWebViewKey
                                                        .currentState
                                                        ?.getPlainText();
                                                if (plainText != null) {
                                                  await Clipboard.setData(
                                                      ClipboardData(
                                                          text: plainText));
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                        content: Text(
                                                            'Text copied to clipboard')),
                                                  );
                                                }
                                              } else if (selected == 'select') {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        SubmissionDescriptionWebViewScreen(
                                                      submissionId:
                                                          widget.uniqueNumber,
                                                      initialHtml:
                                                          submissionDescription,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            child: SubmissionDescriptionWebView(
                                              key: _submissionWebViewKey,
                                              submissionId: widget.uniqueNumber,
                                              initialHtml:
                                                  submissionDescription,
                                              enableTextSelection: false,
                                              forceHybridComposition: false,
                                              routeDetached:
                                                  _isPostWebViewDetached,
                                              enableScrollPerformancePause:
                                                  _webViewScrollOptimizationEnabled &&
                                                      _enableScrollWebViewPause,
                                              onHeightChanged: (double height) {
                                                if (!_webViewLoaded) {
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 25),
                                                      () {
                                                    if (mounted) {
                                                      setState(() {
                                                        _webViewLoaded = true;
                                                      });
                                                    }
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      const Divider(
                                        height: 2.0,
                                        color: Color(0xFF111111),
                                        thickness: 2.0,
                                      ),
                                      const Divider(
                                        height: 3.0,
                                        color: Colors.black,
                                        thickness: 3.0,
                                      ),
                                      const Divider(
                                        height: 4.0,
                                        color: Color(0xFF111111),
                                        thickness: 4.0,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            right: 0.0,
                                            left: 0.0,
                                            top: 11.0,
                                            bottom: 0.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            _buildPublicationAndViewsRow(),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 0.0, top: 11.0),
                                              child: const Divider(
                                                height: 3.0,
                                                color: Color(0xFF111111),
                                                thickness: 3.0,
                                              ),
                                            ),
                                            SizedBox(
                                              height: 50,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceEvenly,
                                                children: [
                                                  /*
                              Expanded(
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.comment_outlined,
                                    size: 26,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AddCommentScreen(
                                          submissionTitle: submissionTitle ?? '',
                                          onSendComment: _addComment,
                                          uniqueNumber: widget.uniqueNumber,
                                        ),
                                      ),
                                    ).then((result) {
                                      if (result == true) {
                                        _fetchPostDetails();
                                      }
                                    });
                                  },
                                  splashRadius: 24,
                                ),
                              ),

                               */
                                                  Expanded(
                                                    child: IconButton(
                                                      icon: const Icon(
                                                        Icons.mail_outline,
                                                        size: 26,
                                                        color: Colors.grey,
                                                      ),
                                                      onPressed: () {
                                                        if (linkUsername !=
                                                            null) {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (context) =>
                                                                  NewMessageScreen(
                                                                recipient:
                                                                    linkUsername!,
                                                              ),
                                                            ),
                                                          );
                                                        } else {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                  'Recipient username is unavailable.'),
                                                              backgroundColor:
                                                                  Colors.red,
                                                            ),
                                                          );
                                                        }
                                                      },
                                                      splashRadius: 24,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: IconButton(
                                                      icon: const Icon(
                                                        Icons
                                                            .photo_library_outlined,
                                                        size: 26,
                                                        color: Colors.grey,
                                                      ),
                                                      onPressed: () {
                                                        if (linkUsername !=
                                                            null) {
                                                          Navigator.push(
                                                            context,
                                                            UserProfileScreen
                                                                .route(
                                                              nickname:
                                                                  linkUsername!,
                                                              initialSection:
                                                                  ProfileSection
                                                                      .Gallery,
                                                            ),
                                                          );
                                                        } else {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                  'Username is unavailable.'),
                                                              backgroundColor:
                                                                  Colors.red,
                                                            ),
                                                          );
                                                        }
                                                      },
                                                      splashRadius: 24,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: IconButton(
                                                      icon: LikeButton(
                                                        isLiked: isFavorited,
                                                        size: 26,
                                                        circleColor:
                                                            const CircleColor(
                                                          start: Colors.red,
                                                          end: Colors.redAccent,
                                                        ),
                                                        bubblesColor:
                                                            const BubblesColor(
                                                          dotPrimaryColor:
                                                              Colors.red,
                                                          dotSecondaryColor:
                                                              Colors.redAccent,
                                                        ),
                                                        likeBuilder:
                                                            (bool isLiked) {
                                                          return Icon(
                                                            isLiked
                                                                ? Icons.favorite
                                                                : Icons
                                                                    .favorite_border,
                                                            color: isLiked
                                                                ? Colors.red
                                                                : Colors.grey,
                                                            size: 26,
                                                          );
                                                        },
                                                        animationDuration:
                                                            const Duration(
                                                                milliseconds:
                                                                    500),
                                                        onTap: _toggleFavorite,
                                                      ),
                                                      onPressed: () {
                                                        _toggleFavorite(
                                                            isFavorited);
                                                      },
                                                      splashRadius: 24,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: IconButton(
                                                      icon: Icon(
                                                        Icons.numbers,
                                                        size: 26,
                                                        color: _showTagsSection
                                                            ? const Color(
                                                                0xFFE09321)
                                                            : Colors.grey,
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          _showTagsSection =
                                                              !_showTagsSection;
                                                        });
                                                      },
                                                      splashRadius: 24,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: IconButton(
                                                      icon: const Icon(
                                                        Icons.share_outlined,
                                                        size: 26,
                                                        color: Colors.grey,
                                                      ),
                                                      onPressed: _sharePost,
                                                      splashRadius: 24,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            AnimatedSize(
                                              duration: const Duration(
                                                  milliseconds: 250),
                                              curve: Curves.easeInOut,
                                              child: _showTagsSection
                                                  ? _buildTagsPanel()
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(
                                        height: 3.0,
                                        color: Color(0xFF111111),
                                        thickness: 3.0,
                                      ),
                                      const Divider(
                                        height: 4.0,
                                        color: Colors.black,
                                        thickness: 4.0,
                                      ),
                                    ],
                                  ),
                                ),
                                ..._buildCommentSlivers(translatorSettings),
                                SliverToBoxAdapter(
                                  child: ListenableBuilder(
                                    listenable: Listenable.merge([
                                      _isCommentComposerExpanded,
                                      _commentDraftCollapsedLines,
                                    ]),
                                    builder: (context, _) {
                                      final isExpanded =
                                          _isCommentComposerExpanded.value;
                                      final collapsedPreviewLines =
                                          _commentDraftCollapsedLines.value;
                                      final composerSpacerHeight = isExpanded
                                          ? 198.0
                                          : (72.0 +
                                              ((collapsedPreviewLines - 1) *
                                                  24.0));
                                      return SizedBox(
                                          height: composerSpacerHeight);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _isCommentComposerExpanded,
                          builder: (context, isExpanded, _) {
                            if (!isExpanded) {
                              return const SizedBox.shrink();
                            }
                            return GestureDetector(
                              onTap: () => FocusScope.of(context).unfocus(),
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.24),
                              ),
                            );
                          },
                        ),
                      ),
                      if (showLoadingIndicator)
                        Container(
                          color: const Color(0xFF000000),
                          child: const Center(
                            child: PulsatingLoadingIndicator(
                              size: 78.0,
                              assetPath: 'assets/icons/fathemed.png',
                            ),
                          ),
                        ),
                      _buildEdgeBackSwipeOverlay(),
                    ],
                  ),
                ),
                bottomNavigationBar: showLoadingIndicator
                    ? null
                    : RepaintBoundary(
                        child: Container(
                          color: Colors.black,
                          child: SafeArea(
                            bottom: true,
                            child: ListenableBuilder(
                              listenable: Listenable.merge([
                                _keyboardInset,
                                _isCommentComposerExpanded,
                              ]),
                              builder: (context, _) {
                                final keyboardInset = _keyboardInset.value;
                                return Padding(
                                  padding: EdgeInsets.only(
                                    left: 8,
                                    right: 8,
                                    bottom: keyboardInset > 0
                                        ? (keyboardInset -
                                                viewPaddingBottom +
                                                8)
                                            .clamp(0.0, double.infinity)
                                        : 0.0,
                                    top: 8,
                                  ),
                                  child: ListenableBuilder(
                                    listenable: Listenable.merge([
                                      _isCommentComposerExpanded,
                                      _commentDraftCollapsedLines,
                                      _commentDraftHasText,
                                      _showScrollToTopNotifier,
                                      _isSendingInlineComment,
                                    ]),
                                    builder: (context, _) {
                                      final isExpanded =
                                          _isCommentComposerExpanded.value;
                                      final collapsedLines =
                                          _commentDraftCollapsedLines.value;
                                      final hasText =
                                          _commentDraftHasText.value;
                                      final isSending =
                                          _isSendingInlineComment.value;
                                      final canSend = !isSending && hasText;
                                      final minLines =
                                          isExpanded ? 6 : collapsedLines;
                                      final maxLines =
                                          isExpanded ? 6 : collapsedLines;
                                      final isCollapsedSingleLine =
                                          !isExpanded && collapsedLines == 1;

                                      const compactSingleLineVerticalPadding =
                                          8.0;
                                      final topPadding = isExpanded
                                          ? 12.0
                                          : (isCollapsedSingleLine
                                              ? compactSingleLineVerticalPadding
                                              : 8.0);
                                      final bottomPadding = isExpanded
                                          ? 8.0
                                          : (isCollapsedSingleLine
                                              ? compactSingleLineVerticalPadding
                                              : 8.0);

                                      return Row(
                                        crossAxisAlignment:
                                            isCollapsedSingleLine
                                                ? CrossAxisAlignment.center
                                                : CrossAxisAlignment.end,
                                        children: [
                                          ClipRect(
                                            child: AnimatedSize(
                                              duration: const Duration(
                                                  milliseconds: 210),
                                              curve: Curves.easeInOut,
                                              alignment: Alignment.centerLeft,
                                              child:
                                                  ValueListenableBuilder<bool>(
                                                valueListenable:
                                                    _showScrollToTopNotifier,
                                                builder: (context, show, _) {
                                                  return Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (show && !isExpanded)
                                                        SizedBox(
                                                          width: 36,
                                                          height: 36,
                                                          child:
                                                              FloatingActionButton
                                                                  .small(
                                                            heroTag:
                                                                'scroll_top',
                                                            backgroundColor:
                                                                const Color(
                                                                    0xFFE09321),
                                                            elevation: 0,
                                                            onPressed: () {
                                                              _scrollController
                                                                  .animateTo(
                                                                0,
                                                                duration:
                                                                    const Duration(
                                                                        milliseconds:
                                                                            300),
                                                                curve: Curves
                                                                    .easeOut,
                                                              );
                                                            },
                                                            child: const Icon(
                                                              Icons
                                                                  .arrow_upward,
                                                              size: 18,
                                                            ),
                                                          ),
                                                        ),
                                                      if (show && !isExpanded)
                                                        const SizedBox(
                                                            width: 8),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Stack(
                                              children: [
                                                Listener(
                                                  behavior: HitTestBehavior
                                                      .translucent,
                                                  onPointerDown:
                                                      _handleCommentComposerPointerDown,
                                                  child: TextField(
                                                    controller:
                                                        _commentController,
                                                    focusNode:
                                                        _commentFocusNode,
                                                    style: const TextStyle(
                                                        color: Colors.white),
                                                    keyboardType:
                                                        TextInputType.multiline,
                                                    textInputAction:
                                                        TextInputAction.newline,
                                                    minLines: minLines,
                                                    maxLines: maxLines,
                                                    scrollPadding:
                                                        const EdgeInsets.only(
                                                            bottom: 8),
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          'Add a comment...',
                                                      hintStyle:
                                                          const TextStyle(
                                                              color: Colors
                                                                  .white54),
                                                      contentPadding:
                                                          EdgeInsets.fromLTRB(
                                                        12,
                                                        topPadding,
                                                        56,
                                                        bottomPadding,
                                                      ),
                                                      filled: true,
                                                      isDense:
                                                          isCollapsedSingleLine,
                                                      fillColor: const Color(
                                                          0xFF151515),
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                        borderSide:
                                                            BorderSide.none,
                                                      ),
                                                    ),
                                                    contextMenuBuilder:
                                                        BBCodeContextMenu.builder(
                                                            _commentController),
                                                  ),
                                                ),
                                                if (isCollapsedSingleLine)
                                                  Positioned.fill(
                                                    child: Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(right: 4),
                                                        child:
                                                            _buildComposerSendButton(
                                                          canSend: canSend,
                                                          isSending: isSending,
                                                          compact: true,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  Positioned(
                                                    top: 4,
                                                    right: 4,
                                                    child:
                                                        _buildComposerSendButton(
                                                      canSend: canSend,
                                                      isSending: isSending,
                                                    ),
                                                  ),
                                                if (isExpanded &&
                                                    hasText &&
                                                    !isSending)
                                                  Positioned(
                                                    right: 4,
                                                    bottom: 4,
                                                    child: IconButton(
                                                      icon: const Icon(
                                                        Icons.clear,
                                                        color: Colors.white54,
                                                      ),
                                                      onPressed: () {
                                                        _commentController
                                                            .clear();
                                                      },
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPublicationAndViewsRow() {
    String? ratingLabel(String? r) {
      switch (r) {
        case 'general':
          return 'General';
        case 'mature':
          return 'Mature';
        case 'adult':
          return 'Adult';
        default:
          return null;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Text(
              '$viewCount',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'Views',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        if (favoritesCount >= 0)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.0),
            child: Icon(Icons.circle, size: 4, color: Colors.grey),
          ),
        if (favoritesCount >= 0)
          Row(
            children: [
              Text(
                '$favoritesCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'Favs',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        if (favoritesCount >= 0 && commentsCount >= 0)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.0),
            child: Icon(Icons.circle, size: 4, color: Colors.grey),
          ),
        if (commentsCount >= 0)
          Row(
            children: [
              Text(
                '$commentsCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'Comments',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        if (commentsCount >= 0 && ratingLabel(rating) != null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.0),
            child: Icon(Icons.circle, size: 4, color: Colors.grey),
          ),
        if (commentsCount >= 0 && ratingLabel(rating) != null)
          Tooltip(
            message: 'Rating: ${ratingLabel(rating)}',
            child: Text(
              ratingLabel(rating)!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.ratingTextColor(rating) ?? Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildCommentSlivers(
    TranslatorSettingsProvider translatorSettings,
  ) {
    if (comments.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding:
                EdgeInsets.only(top: 10.0, bottom: 14.0, right: 8.0, left: 8.0),
            child: Text(
              "No comments.",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding:
            const EdgeInsets.only(top: 8.0, bottom: 0.0, right: 8.0, left: 8.0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final comment = comments[index];
              final selectionId = _commentSelectionId(comment, index);
              final previousComment = index > 0 ? comments[index - 1] : null;
              final nextComment =
                  index + 1 < comments.length ? comments[index + 1] : null;
              final previousNestingLevel = previousComment == null
                  ? 0
                  : ((100.0 - (previousComment['width'] ?? 100).toDouble()) /
                          3.0)
                      .round()
                      .clamp(0, 4)
                      .toInt();
              final nextNestingLevel = nextComment == null
                  ? 0
                  : ((100.0 - (nextComment['width'] ?? 100).toDouble()) / 3.0)
                      .round()
                      .clamp(0, 4)
                      .toInt();
              return CommentWidget(
                key: ValueKey(comment['commentId'] ?? index),
                comment: comment,
                previousNestingLevel: previousNestingLevel,
                nextNestingLevel: nextNestingLevel,
                onHide: () {
                  final hideLink = comment['hideLink'] as String?;
                  final cId = comment['commentId'] as String?;
                  if (hideLink != null && cId != null) {
                    hideComment(hideLink, cId);
                  }
                },
                onEdit: () {
                  if (comment['editLink'] != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditCommentScreen(
                          comment: comment,
                          editLink: comment['editLink'],
                          onUpdateComment: () async {
                            await _fetchPostDetails();
                          },
                        ),
                      ),
                    );
                  }
                },
                onReply: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReplyScreen(
                        comment: {
                          ...comment,
                          'html': comment['commentHtml'],
                        },
                        uniqueNumber: widget.uniqueNumber,
                        isClassic: _isClassicUserPage,
                        onSendReply: (_) {},
                      ),
                    ),
                  );
                  if (result == true) {
                    _fetchPostDetails();
                  }
                },
                onUnhide:
                    (comment['deleted'] == true && comment['hideLink'] != null)
                        ? () => _unhideComment(comment['hideLink'], "")
                        : null,
                handleLink: (url) async {
                  final commentHtml = comment['commentHtml'] ?? '';
                  await _handleCommentLink(context, url, commentHtml);
                },
                selectionAreaKey: _commentSelectionKeyFor(selectionId),
                onSelectionChanged: (content) =>
                    _updateCommentSelectedText(selectionId, content),
                contextMenuBuilder: ReadOnlySelectionContextMenu.builder(
                  selectedTextProvider: () =>
                      _selectedCommentTextFor(selectionId),
                  includeIosTranslate: true,
                ),
                showTranslateButton: _shouldOfferCommentTranslation(
                  comment,
                  translatorSettings,
                  onLanguageDetectionUpdated:
                      _handleTranslationLanguageDetected,
                ),
                onTranslateToggle: () => _openCommentTranslation(
                  comment,
                  translatorSettings,
                ),
              );
            },
            childCount: comments.length,
          ),
        ),
      ),
    ];
  }
}

class _AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
}
