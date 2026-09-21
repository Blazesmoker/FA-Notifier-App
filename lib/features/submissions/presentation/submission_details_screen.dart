import 'package:fanotifier/features/comments/presentation/comment_selection_controller.dart';
import 'widgets/submission_detail_sections.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_action_bar.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_tags_panel.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_statistics_row.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_dialogs.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/scheduler.dart';
import 'package:fanotifier/features/comments/presentation/reply_screen.dart';
import 'package:fanotifier/features/comments/presentation/inline_comment_composer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:fanotifier/shared/fa/fa_username.dart';
import 'package:fanotifier/shared/utils/comment_composer_lines.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/features/submissions/presentation/submission_description_webview.dart';
import 'package:fanotifier/features/profile/presentation/image_inspect_screen.dart';
import 'package:fanotifier/features/submissions/domain/submission_document_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_details_load_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_media_export_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_action_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_details_repository.dart';
import 'package:fanotifier/features/submissions/domain/submission_delete_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_attachment.dart';
import 'package:fanotifier/features/submissions/presentation/submission_details_controller.dart';
import 'package:fanotifier/features/submissions/presentation/submission_favorite_state_controller.dart';
import 'package:fanotifier/features/submissions/presentation/edit_submission_screen.dart';
import 'package:fanotifier/features/submissions/presentation/manage_submissions_screen.dart';
import 'package:fanotifier/features/comments/presentation/edit_comment_screen.dart';
import 'package:fanotifier/features/comments/presentation/threaded_comments.dart';
import 'package:fanotifier/features/comments/presentation/comment_settings_provider.dart';
import 'package:fanotifier/features/search/presentation/keyword_search_screen.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:fanotifier/features/journals/presentation/journal_details_screen.dart';
import 'package:fanotifier/features/comments/presentation/fa_comment_widget.dart';
import 'package:fanotifier/features/submissions/presentation/submission_content.dart';
import 'package:fanotifier/features/profile/domain/profile_section.dart';
import 'package:fanotifier/core/preferences/translator_settings_provider.dart';
import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/presentation/time_display_settings_provider.dart';
import 'package:fanotifier/shared/utils/time_display_formatter.dart';
import 'package:fanotifier/shared/utils/fa_link_matcher.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/navigation/detachable_webview_route_registry.dart';
import 'package:fanotifier/shared/translation/ios_scroll_recovery.dart';
import 'package:fanotifier/shared/translation/native_translate_launcher.dart';
import 'package:fanotifier/shared/translation/translation_service.dart';
import 'package:fanotifier/shared/translation/translation_source_text_builder.dart';
import 'package:fanotifier/shared/platform/fa_share_service.dart';
import 'package:fanotifier/shared/navigation/transparent_slide_page_route.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';

import '../../../shared/utils/bbcode_context_menu.dart';

enum _WatchOutcome { missingAuth, success, failed, error }

class SubmissionDetailsScreen extends StatefulWidget {
  final String imageUrl;
  final String submissionId;
  final bool skipInitialWatchCheck;
  final SubmissionDetailsRepository? repository;

  const SubmissionDetailsScreen({
    required this.imageUrl,
    required this.submissionId,
    this.skipInitialWatchCheck = false,
    this.repository,
    super.key,
  });

  static Route<T> route<T>({
    required String imageUrl,
    required String submissionId,
    bool skipInitialWatchCheck = false,
    RouteSettings? settings,
  }) {
    Widget builder(BuildContext context) => SubmissionDetailsScreen(
          imageUrl: imageUrl,
          submissionId: submissionId,
          skipInitialWatchCheck: skipInitialWatchCheck,
        );

    if (Platform.isAndroid || Platform.isIOS) {
      return TransparentSlidePageRoute<T>(
        settings: settings ??
            const AnalyticsRouteSettings(AppScreens.submissionDetails),
        builder: builder,
      );
    }

    return MaterialPageRoute<T>(
      settings: settings ??
          const AnalyticsRouteSettings(AppScreens.submissionDetails),
      builder: builder,
    );
  }

  @override
  State<SubmissionDetailsScreen> createState() => _SubmissionDetailsScreenState();
}

class _SubmissionDetailsScreenState extends State<SubmissionDetailsScreen>
    with RouteAware, WidgetsBindingObserver, TickerProviderStateMixin
    implements DetachableWebViewRouteOwner {
  bool _showFullPublicationDate = false;
  late final SubmissionDetailsController _controller;
  final TranslationService _translationService = TranslationService.instance;
  final TranslationSourceTextBuilder _translationSourceTextBuilder =
      TranslationSourceTextBuilder(TranslationService.instance);
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _commentComposerFocusRequestedByUser = false;
  bool _blockRestoredCommentComposerFocus = true;
  late final SubmissionFavoriteStateController _favoriteStateController;
  bool _observedFavoriteState = false;
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
  bool _isPostWebViewDetached = false;
  bool _suppressNextRouteDetach = false;
  bool _enableScrollWebViewPause = false;
  int _frameTimingCount = 0;
  int _frameTimingTotalMicros = 0;
  bool _webViewLoaded = false;
  Color? _submissionSnackBarColor;
  int _submissionSnackBarGeneration = 0;
  final GlobalKey<SubmissionDescriptionWebViewState> _submissionWebViewKey =
      GlobalKey<SubmissionDescriptionWebViewState>();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<SelectionAreaState> _titleSelectionKey = GlobalKey();
  final GlobalKey<SelectionAreaState> _submissionContentSelectionKey =
      GlobalKey();
  late final CommentSelectionController _commentSelection =
      CommentSelectionController(
        otherSelectionKeys: [_titleSelectionKey, _submissionContentSelectionKey],
      );
  String _titleSelectedText = '';
  String _submissionContentSelectedText = '';
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

  String? get profileImageUrl => _controller.profileImageUrl;
  String? get username => _controller.username;
  String? get linkUsername => _controller.linkUsername;
  String? get submissionTitle => _controller.submissionTitle;
  String? get fullViewImageUrl => _controller.fullViewImageUrl;
  String? get submissionDescription => _controller.submissionDescription;
  SubmissionAttachment? get submissionAttachment =>
      _controller.submissionAttachment;
  DateTime? get publicationTime => _controller.publicationTime;
  String? get rating => _controller.rating;
  int get favoritesCount {
    final parsedState = _controller.isFavorited;
    final effectiveState = isFavorited;
    final delta = effectiveState == parsedState
        ? 0
        : effectiveState
            ? 1
            : -1;
    return max(0, _controller.favoritesCount + delta);
  }
  int get viewCount => _controller.viewCount;
  int get commentsCount => _controller.commentsCount;
  List<Map<String, dynamic>> get comments => _controller.comments;
  String? get currentUsername => _controller.currentUsername;
  bool get isFavorited => _favoriteStateController.valueFor(
        widget.submissionId,
        _controller.isFavorited,
      );
  String? get watchLink => _controller.watchLink;
  String? get unwatchLink => _controller.unwatchLink;
  String? get blockLink => _controller.blockLink;
  String? get unblockLink => _controller.unblockLink;
  bool get isWatching => _controller.isWatching;
  bool get _watchLinksLoading => _controller.watchLinksLoading;
  bool get _watchRequestInFlight => _controller.watchRequestInFlight;
  bool get isBlocked => _controller.isBlocked;
  String? get category => _controller.category;
  String? get type => _controller.type;
  String? get species => _controller.species;
  String? get gender => _controller.gender;
  String? get size => _controller.size;
  String? get fileSize => _controller.fileSize;
  List<SubmissionFolderLink> get folders => _controller.folders;
  List<FaPostTag> get keywordTags => _controller.keywordTags;
  List<FaPostTag> get metaKeywordTags => _controller.metaKeywordTags;
  String? get tagBlocklistNonce => _controller.tagBlocklistNonce;
  bool get _isClassicUserPage => _controller.isClassicUserPage;
  double? get imageWidth => _controller.imageWidth;
  double? get imageHeight => _controller.imageHeight;
  bool get _detailsLoaded => _controller.detailsLoaded;

  @override
  void initState() {
    super.initState();
    _controller = SubmissionDetailsController(
      submissionId: widget.submissionId,
      repository: widget.repository ?? context.read<SubmissionDetailsRepository>(),
    );
    _favoriteStateController =
        context.read<SubmissionFavoriteStateController>();
    _observedFavoriteState = isFavorited;
    _favoriteStateController.addListener(_handleFavoriteStateChanged);
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

  void _showSubmissionMessage(String message, Color backgroundColor) {
    if (!mounted) return;
    final generation = ++_submissionSnackBarGeneration;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (_submissionSnackBarColor != backgroundColor) {
      setState(() {
        _submissionSnackBarColor = backgroundColor;
      });
    }
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
    unawaited(
      controller.closed.then((_) {
        if (!mounted || generation != _submissionSnackBarGeneration) return;
        setState(() {
          _submissionSnackBarColor = null;
        });
      }),
    );
  }

  @override
  void dispose() {
    _favoriteStateController.removeListener(_handleFavoriteStateChanged);
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

  void _handleFavoriteStateChanged() {
    final nextState = isFavorited;
    if (!mounted || nextState == _observedFavoriteState) return;
    _observedFavoriteState = nextState;
    setState(() {});
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
    if (_suppressNextRouteDetach ||
        DetachableWebViewRouteRegistry.routeDetachSuppressed) {
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

  Future<void> _prepareForInternalWebViewNavigation() async {
    _setRouteWebViewDetached(true);
    await WidgetsBinding.instance.endOfFrame;
    if (Platform.isAndroid) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
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

  void _updateTitleSelectedText(SelectedContent? content) {
    _titleSelectedText = content?.plainText ?? '';
  }

  void _updateSubmissionContentSelectedText(SelectedContent? content) {
    _submissionContentSelectedText = content?.plainText ?? '';
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

  Future<void> _openSubmissionTranslation(
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
        _dismissCommentComposerFocus();
      }
    }
  }

  Future<void> _loadSfwEnabled() async {
    await _controller.loadSfwEnabled();
    setState(() {});
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
    final updated = await _controller.loadUserActions(
      confirmNsfw: _showNSFWConfirmationDialog,
      onNsfwAllowed: () {
        if (mounted) setState(() {});
      },
    );
    if (updated && mounted) setState(() {});
  }

  Widget _buildTagsPanel() {
    return buildSubmissionTagsPanel(
      keywordTags: keywordTags,
      metaKeywordTags: metaKeywordTags,
      tagToggleInFlight: _tagToggleInFlight,
      onToggleTagBlock: _toggleTagBlock,
      onSearch: _navigateToSearch,
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
      if (!mounted) return;
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
    final updated = _controller.applyLocalTagBlockState(
      tagName,
      isBlocked: isBlocked,
    );
    if (updated) setState(() {});
  }

  Future<void> _sendTagBlocklistRequest(String tagName,
      {required bool shouldBlock}) {
    return _controller.updateTagBlocklist(
      tagName,
      shouldBlock: shouldBlock,
    );
  }

  void _navigateToSearch(String keyword) {
    String formattedKeyword = '@keywords $keyword';

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const AnalyticsRouteSettings(AppScreens.keywordSearch),
        builder: (context) =>
            KeywordSearchScreen(initialKeyword: formattedKeyword),
      ),
    );
  }

  Future<void> _handleBlockUnblock() async {
    // When we skipped initial fetch, load links on first use (same as Watch)
    if (blockLink == null && unblockLink == null && username != null) {
      setState(() => _controller.setWatchLinksLoading(true));
      await _fetchUserPageLinks();
      if (!mounted) return;
      setState(() => _controller.setWatchLinksLoading(false));
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
      final key = _controller.blockActionKey(shouldBlock: false);
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
      final key = _controller.blockActionKey(shouldBlock: true);
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
      final result =
          await _controller.performBlockUnblock(urlPath, keyValue);

      if (!mounted) return;
      if (result.status == SubmissionActionStatus.missingAuth) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to perform this action.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (result.status == SubmissionActionStatus.success) {
        await _fetchUserPageLinks();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              shouldBlock ? 'Author blocked' : 'Author unblocked',
            ),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'An error occurred while trying to ${shouldBlock ? 'block' : 'unblock'} author.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<_WatchOutcome> _sendWatchUnwatchRequest(String urlPath,
      {required bool shouldWatch}) async {
    try {
      final result = await _controller.performWatchUnwatch(urlPath);
      if (result.status == SubmissionActionStatus.missingAuth) {
        return _WatchOutcome.missingAuth;
      }
      if (result.status == SubmissionActionStatus.success) {
        await _fetchUserPageLinks();
        return _WatchOutcome.success;
      }
      debugPrint(
          'Failed to ${shouldWatch ? 'watch' : 'unwatch'} user. Status code: ${result.statusCode}');
      return _WatchOutcome.failed;
    } catch (e) {
      debugPrint('Error during ${shouldWatch ? 'watch' : 'unwatch'}: $e');
      return _WatchOutcome.error;
    }
  }

  void _showWatchOutcomeSnackBar(_WatchOutcome outcome,
      {required bool shouldWatch}) {
    final messenger = rootMessengerKey.currentState;
    if (messenger == null) return;
    switch (outcome) {
      case _WatchOutcome.missingAuth:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Please log in to perform this action.'),
            backgroundColor: Colors.red,
          ),
        );
      case _WatchOutcome.success:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              shouldWatch
                  ? 'Now watching $username'
                  : 'Stopped watching $username',
            ),
            backgroundColor: Colors.green,
          ),
        );
      case _WatchOutcome.failed:
        messenger.showSnackBar(
          SnackBar(
            content:
                Text('Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
            backgroundColor: Colors.red,
          ),
        );
      case _WatchOutcome.error:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _handleWatchButtonPressed() async {
    if (_watchRequestInFlight) return;
    // When we skipped initial fetch (Browse/Search), fetch links on first tap
    if (watchLink == null && unwatchLink == null && username != null) {
      if (_watchLinksLoading) return;
      setState(() => _controller.setWatchLinksLoading(true));
      await _fetchUserPageLinks();
      if (!mounted) return;
      setState(() => _controller.setWatchLinksLoading(false));
      // After fetch: if already watching, button will show -Watch; else send watch request below
    }
    setState(() => _controller.setWatchRequestInFlight(true));
    final shouldWatch = !isWatching;
    var outcome = _WatchOutcome.failed;
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
      if (mounted) {
        setState(() => _controller.setWatchRequestInFlight(false));
      }
    }
    _showWatchOutcomeSnackBar(outcome, shouldWatch: shouldWatch);
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
        final statusCode = await _controller.sendAuthenticatedGet(hideLink);
        if (!mounted) return;
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

  Future<void> _fetchPostDetails() async {
    setState(_controller.startLoading);

    if (!await _controller.hasAuthCookies()) {
      setState(_controller.stopLoading);
      return;
    }

    try {
      final result = await _controller.loadDetails(
        confirmNsfw: _showNSFWConfirmationDialog,
        onNsfwAllowed: () => setState(() {}),
      );
      _observedFavoriteState = isFavorited;
      setState(() {});

      if (result.status == SubmissionDetailsLoadStatus.httpFailure) {
        debugPrint('Failed to fetch post details: ${result.statusCode}');

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

      if (result.status == SubmissionDetailsLoadStatus.matureWarning) {
        debugPrint(
            'ERROR: Still got mature warning after retry - this should not happen');
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

      debugPrint('Post loaded successfully: $submissionTitle');
    } catch (e) {
      debugPrint('Error fetching post details: $e');
      setState(() {});

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
      final result = await _controller.prepareDeletion();

      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An unexpected error occurred.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDeleteConfirmationDialog(
    SubmissionDeleteConfirmationData confirmationData,
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
        return buildSubmissionDeleteDialog(
          dialogContext: dialogContext,
          fullViewImageUrl: fullViewImageUrl,
          currentUsername: currentUsername,
          passwordController: passwordController,
          passwordFocusNode: passwordFocusNode,
          submitDeletion: submitDeletion,
        );
      },
    ).then((_) {
      passwordController.dispose();
      passwordFocusNode.dispose();
    });
  }

  Future<void> _confirmDeletion(
    SubmissionDeleteConfirmationData confirmationData,
    String password,
  ) async {
    try {
      final success = await _controller.confirmDeletion(
        confirmationData: confirmationData,
        password: password,
      );

      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An error occurred while deleting the submission.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showInfoDialog() async {
    _dismissCommentComposerFocus();
    _suppressNextRouteDetach = true;
    final selectedFolder = await showDialog<SubmissionFolderLink>(
      context: context,
      builder: (dialogContext) {
        return buildSubmissionInfoDialog(
          dialogContext: dialogContext,
          category: category,
          type: type,
          species: species,
          gender: gender,
          size: size,
          fileSize: fileSize,
          folders: folders,
        );
      },
    ).whenComplete(() {
      _suppressNextRouteDetach = false;
    });

    if (!mounted || selectedFolder == null) return;
    await handleFALink(context, selectedFolder.url);
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

  String? getFormattedPublicationTime({required TimeDisplayFormat format}) {
    if (publicationTime == null) return null;
    return formatLocalDateTime(
      publicationTime!,
      format: format,
    );
  }

  void _sharePost() {
    final postUrl = _controller.submissionViewUrl;
    final shareContent = postUrl;
    const FaShareService().shareText(
      text: shareContent,
      subject: submissionTitle ?? 'Fur Affinity Post',
    );
  }

  void _addComment(String commentText) {
    setState(() => _controller.addComment(commentText));
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
      final success = await _controller.submitComment(commentText);

      if (!mounted) return;

      if (success) {
        _addComment(commentText);
        _commentController.clear();
        _commentFocusNode.unfocus();
        await _fetchPostDetails();

        if (!mounted) return;
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
        final statusCode =
            await _controller.sendAuthenticatedGet(unhideLink);
        if (!mounted) return;
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
      final result = await _controller.exportToGallery(imageUrl);
      if (!context.mounted) return;
      if (result.status == SubmissionMediaExportStatus.permissionDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo permission denied'),
            backgroundColor: Colors.red,
          ),
        );
      } else if (result.status == SubmissionMediaExportStatus.success) {
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
      if (!context.mounted) return;
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
      final result = await _controller.shareFromUrl(imageUrl);
      if (!context.mounted) return;
      if (result.status == SubmissionMediaExportStatus.permissionDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission denied'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String fixTruncatedLinks(String htmlContent) {
    return _controller.normalizeSubmissionHtml(htmlContent);
  }

  /// Returns the full URL from a truncated comment link.
  String? _getFullLinkFromCommentHtml(String commentHtml, String truncatedUrl) {
    return _controller.findFullCommentLink(commentHtml, truncatedUrl);
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
            initialSection: ProfileSection.gallery,
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
            initialSection: ProfileSection.gallery,
            initialFolderUrl: folderUrl,
            initialFolderName: folderName,
          ),
        );
        return;
      case FALinkTargetType.scraps:
        Navigator.push(
          context,
          UserProfileScreen.route(
            nickname: target.username!,
            initialSection: ProfileSection.scraps,
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
            initialSection: ProfileSection.journals,
          ),
        );
        return;
      case FALinkTargetType.journal:
        Navigator.push(
          context,
          MaterialPageRoute(
            settings:
                const AnalyticsRouteSettings(AppScreens.journalDetails),
            builder: (context) => JournalDetailsScreen(journalId: target.journalId!),
          ),
        );
        return;
      case FALinkTargetType.submission:
        Navigator.push(
          context,
          SubmissionDetailsScreen.route(
            submissionId: target.submissionId!,
            imageUrl: '',
          ),
        );
        return;
      case FALinkTargetType.external:
        await handleExternalLink(context, fullUrl);
        return;
    }
  }

  Future<void> _showEditDialog() async {
    _dismissCommentComposerFocus();
    _suppressNextRouteDetach = true;
    String? type;
    try {
      type = await showDialog<String>(
        context: context,
        builder: (context) {
          return buildSubmissionEditDialog(
          context: context,
        );
        },
      );
    } finally {
      _suppressNextRouteDetach = false;
    }

    if (!mounted || type == null) return;
    await _openSubmissionEdit(type);
  }

  Future<void> _openSubmissionEdit(String type) async {
    late final String editUrl;
    late final String title;
    switch (type) {
      case 'info':
        editUrl = _controller.buildChangeInfoUrl();
        title = 'Edit Submission Info';
        break;
      case 'thumbnail':
        editUrl = _controller.buildChangeThumbnailUrl();
        title = 'Update Thumbnail';
        break;
      case 'file':
        editUrl = _controller.buildChangeSubmissionUrl();
        title = 'Update Source File';
        break;
      default:
        return;
    }

    await _prepareForInternalWebViewNavigation();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const AnalyticsRouteSettings(AppScreens.editSubmission),
        builder: (context) => EditSubmissionScreen(
          initialUrl: editUrl,
          title: title,
        ),
      ),
    );
    if (!mounted) return;
    _fetchPostDetails();
  }

  Future<void> _openManageSubmissions() async {
    await _prepareForInternalWebViewNavigation();
    if (!mounted) return;
    await Navigator.of(context).push(ManageSubmissionsScreen.route());
    if (!mounted) return;
    await _fetchPostDetails();
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

    return _favoriteStateController.toggle(
      submissionId: widget.submissionId,
      fallbackIsFavorite: _controller.isFavorited,
      favUrl: _controller.favLink,
      unfavUrl: _controller.unfavLink,
      sfwEnabled: _controller.sfwEnabled,
    );
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
    final commentSettings = context.watch<CommentSettingsProvider>();
    final submissionTimeFormat =
        context.select<TimeDisplaySettingsProvider, TimeDisplayFormat>(
      (settings) => settings.formatFor(
        TimeDisplayOccasion.submissionPublication,
      ),
    );
    final formattedPublicationTime = getFormattedPublicationTime(
      format: submissionTimeFormat,
    );
    final bool showLoadingIndicator = !_detailsLoaded || !_webViewLoaded;
    final double viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
    return ExcludeSemantics(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor:
              _submissionSnackBarColor ?? Colors.black,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
          statusBarColor: const Color(0xFF111111),
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
                        final menuItems = buildSubmissionActionMenu(
                          currentUsername: currentUsername,
                          username: username,
                          isBlocked: isBlocked,
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

                            if (!context.mounted) return;
                            switch (selected) {
                              case 'report':
                                launchUrlString(_controller.troubleTicketsUrl);
                                break;
                              case 'block_unblock':
                                await _handleBlockUnblock();
                                break;
                              case 'info':
                                await _showInfoDialog();
                                break;
                              case 'edit':
                                await _showEditDialog();
                                break;
                              case 'manage':
                                await _openManageSubmissions();
                                break;
                              case 'delete':
                                _handleDeletePost();
                                break;
                              case 'copy_link':
                                final postUrl = _controller.submissionViewUrl;
                                await Clipboard.setData(
                                    ClipboardData(text: postUrl));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Link copied to clipboard'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                                break;
                              case 'translate':
                                await _openSubmissionTranslation(translatorSettings);
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
                body: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown:
                      _commentSelection.handleSelectionClearPointerDown,
                  onPointerMove:
                      _commentSelection.handleSelectionClearPointerMove,
                  onPointerUp:
                      _commentSelection.handleSelectionClearPointerUp,
                  onPointerCancel:
                      _commentSelection.handleSelectionClearPointerCancel,
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
                                        buildSubmissionAuthorHeader(
                                          profileImageUrl: profileImageUrl!,
                                          username: username!,
                                          currentUsername: currentUsername,
                                          iconBeforeUrls: iconBeforeUrls,
                                          iconAfterUrls: iconAfterUrls,
                                          watchLinksLoading: _watchLinksLoading,
                                          watchRequestInFlight: _watchRequestInFlight,
                                          isWatching: isWatching,
                                          onAuthorTap: () {
                                            Navigator.push(
                                              context,
                                              UserProfileScreen.route(
                                                nickname: linkUsername ?? username!,
                                              ),
                                            );
                                          },
                                          onWatchPressed: _handleWatchButtonPressed,
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
                                              if (!context.mounted) return;
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
                                            child: buildSubmissionImage(
                                              imageUrl: fullViewImageUrl!,
                                              imageWidth: imageWidth,
                                              imageHeight: imageHeight,
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
                                                      formattedPublicationTime ??
                                                          '',
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
                                      if (submissionAttachment != null)
                                        SubmissionContent(
                                          attachment: submissionAttachment!,
                                          onDownload: () =>
                                              _controller.downloadSubmissionFile(
                                            submissionAttachment!,
                                          ),
                                          onShowMessage:
                                              _showSubmissionMessage,
                                          routeDetached:
                                              _isPostWebViewDetached,
                                          selectionAreaKey:
                                              _submissionContentSelectionKey,
                                          onSelectionChanged:
                                              _updateSubmissionContentSelectedText,
                                          contextMenuBuilder:
                                              ReadOnlySelectionContextMenu
                                                  .builder(
                                            selectedTextProvider: () =>
                                                _submissionContentSelectedText,
                                            includeIosTranslate: true,
                                          ),
                                        ),
                                      if (submissionAttachment != null &&
                                          submissionDescription != null)
                                        const Divider(
                                          height: 2.0,
                                          color: Color(0xFF111111),
                                          thickness: 2.0,
                                        ),
                                      if (submissionAttachment != null &&
                                          submissionDescription != null)
                                        const Divider(
                                          height: 3.0,
                                          color: Colors.black,
                                          thickness: 3.0,
                                        ),
                                      if (submissionAttachment != null &&
                                          submissionDescription != null)
                                        const Divider(
                                          height: 4.0,
                                          color: Color(0xFF111111),
                                          thickness: 4.0,
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
                                              if (!context.mounted) return;
                                              if (selected == 'copy') {
                                                String? plainText =
                                                    await _submissionWebViewKey
                                                        .currentState
                                                        ?.getPlainText();
                                                if (plainText != null) {
                                                  await Clipboard.setData(
                                                      ClipboardData(
                                                          text: plainText));
                                                  if (!context.mounted) return;
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
                                                    settings:
                                                        const AnalyticsRouteSettings(
                                                      AppScreens.documentViewer,
                                                    ),
                                                    builder: (context) =>
                                                        SubmissionDescriptionWebViewScreen(
                                                      submissionId:
                                                          widget.submissionId,
                                                      initialHtml:
                                                          submissionDescription,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            child: SubmissionDescriptionWebView(
                                              key: _submissionWebViewKey,
                                              submissionId: widget.submissionId,
                                              initialHtml:
                                                  submissionDescription,
                                              enableTextSelection: false,
                                              forceHybridComposition: false,
                                              routeDetached:
                                                  _isPostWebViewDetached,
                                              onBeforeInternalNavigation:
                                                  _prepareForInternalWebViewNavigation,
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
                                            buildSubmissionActionBar(
                                              context: context,
                                              getLinkUsername: () => linkUsername,
                                              isFavorited: isFavorited,
                                              showTagsSection: _showTagsSection,
                                              onToggleFavorite: _toggleFavorite,
                                              onToggleTags: () {
                                                setState(() {
                                                  _showTagsSection = !_showTagsSection;
                                                });
                                              },
                                              onShare: _sharePost,
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
                                ..._buildCommentSlivers(
                                  translatorSettings,
                                  commentSettings.collapsibleCommentsEnabled,
                                ),
                                SliverToBoxAdapter(
                                  child: ValueListenableBuilder<int>(
                                    valueListenable:
                                        _commentDraftCollapsedLines,
                                    builder:
                                        (context, collapsedPreviewLines, _) {
                                      final composerSpacerHeight =
                                          inlineCommentComposerClearance(
                                        collapsedLines: collapsedPreviewLines,
                                        viewPaddingBottom: viewPaddingBottom,
                                      );
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
                      if (!showLoadingIndicator)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: InlineCommentComposer(
                            controller: _commentController,
                            focusNode: _commentFocusNode,
                            keyboardInset: _keyboardInset,
                            isExpanded: _isCommentComposerExpanded,
                            collapsedLines: _commentDraftCollapsedLines,
                            hasText: _commentDraftHasText,
                            showScrollToTop: _showScrollToTopNotifier,
                            isSending: _isSendingInlineComment,
                            viewPaddingBottom: viewPaddingBottom,
                            scrollToTopHeroTag: 'scroll_top',
                            onPointerDown:
                                _handleCommentComposerPointerDown,
                            onScrollToTop: () {
                              _scrollController.animateTo(
                                0,
                                duration:
                                    const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            },
                            onSend: _sendInlineComment,
                            onKeyboardClosing: _dismissCommentComposerFocus,
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPublicationAndViewsRow() {
    return buildSubmissionStatisticsRow(
      viewCount: viewCount,
      favoritesCount: favoritesCount,
      commentsCount: commentsCount,
      rating: rating,
    );
  }

  List<Widget> _buildCommentSlivers(
    TranslatorSettingsProvider translatorSettings,
    bool collapsibleCommentsEnabled,
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
        sliver: SliverThreadedComments(
          comments: comments,
          collapsible: collapsibleCommentsEnabled,
          itemBuilder: (context, item) {
            final index = item.index;
            final comment = item.comment;
            final selectionId = _commentSelection.commentSelectionId(comment, index);
            return FaCommentWidget(
                timeDisplayOccasion: TimeDisplayOccasion.submissionComment,
                htmlCachePolicy: CommentHtmlCachePolicy.onWidgetUpdate,
                showUnhide: comment['hideLink'] != null,
                key: ValueKey(comment['commentId'] ?? index),
                comment: comment,
                treeLevels: item.treeLevels,
                collapsed: item.collapsed,
                onToggleCollapse: item.onToggleCollapse,
                hasAnyCommentSelection: () => _commentSelection.hasSelection,
                animationDuration: item.animationDuration,
                animationCurve: item.animationCurve,
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
                        settings:
                            const AnalyticsRouteSettings(AppScreens.editComment),
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
                      settings: const AnalyticsRouteSettings(
                        AppScreens.replyToComment,
                      ),
                      builder: (context) => ReplyScreen(
                        comment: {
                          ...comment,
                          'html': comment['commentHtml'],
                        },
                        submissionId: widget.submissionId,
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
                selectionAreaKey: _commentSelection.commentSelectionKeyFor(selectionId),
                onSelectionChanged: (content) =>
                    _commentSelection.updateCommentSelectedText(selectionId, content),
                contextMenuBuilder: ReadOnlySelectionContextMenu.builder(
                  selectedTextProvider: () =>
                      _commentSelection.selectedCommentTextFor(selectionId),
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
        ),
      ),
    ];
  }
}
