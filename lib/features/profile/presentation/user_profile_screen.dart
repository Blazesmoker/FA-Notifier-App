import 'package:fanotifier/features/profile/presentation/user_profile_details_header.dart';
import 'package:fanotifier/features/profile/presentation/profile_tab_scroll_scope.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_edit_dialog.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_delete_shouts_dialog.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_avatar.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_header_name.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:fanotifier/features/profile/presentation/user_description_webview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:fanotifier/features/profile/domain/profile_section.dart';
import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/features/profile/domain/user_profile_api_models.dart';
import 'package:fanotifier/features/profile/domain/user_profile_shout_deletion_result.dart';
import 'package:fanotifier/features/profile/domain/user_profile_repository.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/features/journals/presentation/create_journal_screen.dart';
import 'package:fanotifier/features/journals/presentation/journal_details_screen.dart';
import 'package:fanotifier/features/submissions/presentation/submission_details_screen.dart';
import 'package:fanotifier/features/profile/presentation/post_shout.dart';
import 'package:fanotifier/features/profile/presentation/profile_journals.dart';
import 'package:fanotifier/features/settings/presentation/contacts_and_media_screen.dart';
import 'package:fanotifier/features/settings/presentation/profile_info_screen.dart';
import 'package:fanotifier/features/settings/presentation/profile_banner_screen.dart';
import 'package:fanotifier/features/settings/presentation/avatar_management_screen.dart';
import 'package:fanotifier/shared/utils/fa_link_matcher.dart';
import 'package:fanotifier/shared/utils/app_snack_bar.dart';
import 'package:fanotifier/shared/navigation/detachable_webview_route_registry.dart';
import 'package:fanotifier/features/profile/domain/user_profile_action_key.dart';
import 'package:fanotifier/features/profile/presentation/profile_banner_header.dart';
import 'package:fanotifier/features/profile/presentation/profile_avatar_transparency_detector.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_controller.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_sliver_helpers.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_favorites_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_gallery_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_home_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_journals_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_scraps_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_shout_selection_controller.dart';
import 'package:fanotifier/features/profile/presentation/profile_animated_media_visibility.dart';
import 'package:fanotifier/core/preferences/translator_settings_provider.dart';
import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/presentation/time_display_settings_provider.dart';
import 'package:fanotifier/shared/translation/ios_scroll_recovery.dart';
import 'package:fanotifier/shared/translation/native_translate_launcher.dart';
import 'package:fanotifier/shared/translation/translation_service.dart';
import 'package:fanotifier/shared/navigation/transparent_slide_page_route.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/core/analytics/app_analytics.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'profile_tab_loading_controller.dart';

class UserProfileScreen extends StatefulWidget {
  final String nickname;
  final ProfileSection initialSection;
  final String? initialFolderUrl;
  final String? initialFolderName;
  final VoidCallback? onProfileChanged;
  const UserProfileScreen({
    super.key,
    required this.nickname,
    this.initialSection = ProfileSection.home,
    this.initialFolderUrl,
    this.initialFolderName,
    this.onProfileChanged,
  });

  static Route<T> route<T>({
    required String nickname,
    ProfileSection initialSection = ProfileSection.home,
    String? initialFolderUrl,
    String? initialFolderName,
    VoidCallback? onProfileChanged,
    RouteSettings? settings,
    bool instant = false,
  }) {
    Widget builder(BuildContext context) => UserProfileScreen(
          nickname: nickname,
          initialSection: initialSection,
          initialFolderUrl: initialFolderUrl,
          initialFolderName: initialFolderName,
          onProfileChanged: onProfileChanged,
        );

    return TransparentSlidePageRoute<T>(
      settings: settings ?? AnalyticsRouteSettings(_screenFor(initialSection)),
      builder: builder,
      routeTransitionDuration:
          instant ? Duration.zero : const Duration(milliseconds: 280),
      routeReverseTransitionDuration:
          instant ? Duration.zero : const Duration(milliseconds: 280),
    );
  }

  static AppScreen _screenFor(ProfileSection section) {
    return switch (section) {
      ProfileSection.home => AppScreens.profileHome,
      ProfileSection.gallery => AppScreens.profileGallery,
      ProfileSection.scraps => AppScreens.profileScraps,
      ProfileSection.favs => AppScreens.profileFavorites,
      ProfileSection.journals => AppScreens.profileJournals,
    };
  }

  @override
  UserProfileScreenState createState() => UserProfileScreenState();
}

class UserProfileScreenState extends State<UserProfileScreen>
    with RouteAware, TickerProviderStateMixin
    implements DetachableWebViewRouteOwner {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    _tabLoadingController.dispose();
    _scrollWebViewResumeTimer?.cancel();
    _moveUpMediaProactiveTimer?.cancel();
    if (_webViewScrollOptimizationEnabled) {
      SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    }
    IosScrollRecovery.removeListener(_handleIosScrollRecovery);
    _backSwipeAnimationController.dispose();
    _tabController.dispose();
    _scrollController.removeListener(_onProfileScroll);
    _scrollController.dispose();
    _backSwipeOffsetNotifier.dispose();
    _showMoveUpFab.dispose();
    _moveUpFabLift.dispose();
    _moveUpMediaProactive.dispose();
    _galleryDetailFetchesActive.dispose();
    _webViewLoaded.dispose();
    _isLoadingMoreShouts.dispose();
    _shoutsRevision.dispose();
    _watchRequestInFlight.dispose();
    _isDeletingSelectedShouts.dispose();
    _profileAvatarBorderVisible.dispose();
    _profileNameRowKey.dispose();
    _shoutSelectionController.dispose();
    DetachableWebViewRouteRegistry.unregister(this);
    routeObserver.unsubscribe(this);
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

  final GlobalKey<ProfileJournalsState> _journalsKey =
      GlobalKey<ProfileJournalsState>();
  GlobalKey<UserDescriptionWebViewState> _webViewKey =
      GlobalKey<UserDescriptionWebViewState>();
  final GlobalKey<ProfileAnimatedMediaVisibilityState>
      _descriptionMediaVisibilityKey =
      GlobalKey<ProfileAnimatedMediaVisibilityState>();
  final GlobalKey<ProfileAnimatedMediaVisibilityState>
      _avatarMediaVisibilityKey =
      GlobalKey<ProfileAnimatedMediaVisibilityState>();
  int _profileMediaRevision = 0;

  late final UserProfileRepository _profileRepository;
  late final UserProfileController _profileController;
  final ProfileAvatarTransparencyDetector _avatarTransparencyDetector =
      const ProfileAvatarTransparencyDetector();
  final TranslationService _translationService = TranslationService.instance;
  final UserProfileShoutSelectionController _shoutSelectionController =
      UserProfileShoutSelectionController();

  Future<void> _loadSfwEnabled() async {
    await _profileController.loadSfwEnabled();
  }

  Future<void> _handleDescriptionLongPress(
      LongPressStartDetails details) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      details.globalPosition & const Size(40, 40),
      Offset.zero & overlay.size,
    );
    _suppressNextRouteDetach = true;
    final selected = await showMenu<String>(
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
      _suppressNextRouteDetach = false;
    });
    if (!mounted) return;
    if (selected == 'copy') {
      final plainText = await _webViewKey.currentState?.getPlainText();
      if (!mounted) return;
      if (plainText != null) {
        await Clipboard.setData(ClipboardData(text: plainText));
        if (!mounted) return;
        showAppSnackBar(context, 'Text copied to clipboard',
            backgroundColor: Colors.green);
      }
    } else if (selected == 'select') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          settings:
              const AnalyticsRouteSettings(AppScreens.documentViewer),
          builder: (context) => UserDescriptionWebViewScreen(
            sanitizedUsername: _profileController.sanitizedUsername,
            initialHtml: _profileController.userDescription,
          ),
        ),
      );
    }
  }

  String _profileTranslationSourceText() {
    return _translationService
        .plainTextFromHtml(_profileController.userDescription ?? '');
  }

  Future<void> _openProfileTranslation() async {
    final settings = context.read<TranslatorSettingsProvider>();
    final webViewText = await _webViewKey.currentState?.getPlainText();
    await NativeTranslateLauncher.open(
      webViewText?.trim().isNotEmpty == true
          ? webViewText!
          : _profileTranslationSourceText(),
      targetLanguageCode: settings.targetLanguageCode,
    );
  }

  final ValueNotifier<bool> _webViewLoaded = ValueNotifier<bool>(false);

  static const double sliverAppBarExpandedHeight = 120.0;
  static const double sliverAppBarMinHeight = kToolbarHeight - 80.0; // 56.0
  static const double collapsibleHeaderMaxHeight = 110.0;
  static const double navigationSliderHeight = 64.0;

  static const double _profileAvatarBehindBannerStart = 63.0;

  static const double _edgeBackSwipeDetectorWidth = 25.0;
  static const double _edgeBackSwipeTriggerWidth = 62.0;
  static const double _edgeBackSwipeMinDistance = 72.0;
  static const double _edgeBackSwipeMinVelocity = 700.0;
  static const double _bulkSelectionMoveUpGap = 8.0;
  static const double _moveUpFabDefaultBottomSpacing = 16.0;
  static const bool _webViewScrollOptimizationEnabled = false;

  late ScrollController _scrollController;
  late final ValueNotifier<bool> _showMoveUpFab = ValueNotifier<bool>(false);
  late final ValueNotifier<double> _moveUpFabLift =
      ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _moveUpMediaProactive =
      ValueNotifier<bool>(false);
  late final ValueNotifier<double> _backSwipeOffsetNotifier =
      ValueNotifier<double>(0.0);
  late final AnimationController _backSwipeAnimationController;
  Animation<double>? _backSwipeOffsetAnimation;
  bool _popAfterBackSwipeAnimation = false;

  late TabController _tabController;

  static const Duration _scrollWebViewResumeDelay = Duration(milliseconds: 50);
  late final ProfileTabLoadingController _tabLoadingController;
  Timer? _scrollWebViewResumeTimer;
  Timer? _moveUpMediaProactiveTimer;
  final Set<ProfileSection> _bulkSelectionActiveSections = <ProfileSection>{};
  final Map<ProfileSection, double> _bulkSelectionBarHeights =
      <ProfileSection, double>{};

  int _previousIndex = 0;

  final ValueNotifier<bool> _isLoadingMoreShouts =
      ValueNotifier<bool>(false);
  final ValueNotifier<int> _shoutsRevision = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isDeletingSelectedShouts =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> _watchRequestInFlight =
      ValueNotifier<bool>(false);
  bool _isDraggingBackFromEdge = false;
  bool _isHomeTabMediaVisible = true;
  bool _isGalleryTabActive = false;
  bool _isProfileRouteCurrent = true;
  late final ValueNotifier<bool> _galleryDetailFetchesActive;
  bool _isProfileWebViewDetached = false;
  bool _suppressNextRouteDetach = false;
  bool _didTemporarilyRestorePreviousForSwipe = false;
  bool _isWebViewPausedForScroll = false;
  bool _enableScrollWebViewPause = false;
  int _frameTimingCount = 0;
  int _frameTimingTotalMicros = 0;
  int _iosScrollRecoveryKey = IosScrollRecovery.revision;
  final ValueNotifier<bool> _profileAvatarBorderVisible =
      ValueNotifier<bool>(false);
  String? _profileAvatarTransparencyCheckedUrl;
  int _profileAvatarTransparencyCheckGeneration = 0;
  double _backDragStartX = 0.0;
  double _backDragDistance = 0.0;

  double get _backSwipeOffset => _backSwipeOffsetNotifier.value;
  set _backSwipeOffset(double value) => _backSwipeOffsetNotifier.value = value;
  bool get _isShoutSelectionMode =>
      _shoutSelectionController.isSelectionMode;

  @override
  void initState() {
    super.initState();
    DetachableWebViewRouteRegistry.register(this);

    final profileRepository = context.read<UserProfileRepository>();
    _profileRepository = profileRepository;
    _profileController = UserProfileController(
      repository: profileRepository,
      nickname: widget.nickname,
    );
    if (_webViewScrollOptimizationEnabled) {
      SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
    }
    IosScrollRecovery.addListener(_handleIosScrollRecovery);

    if (widget.initialSection != ProfileSection.home) {
      _webViewLoaded.value = true;
    }

    _scrollController = ScrollController();
    _scrollController.addListener(_onProfileScroll);

    _tabController = TabController(
      length: ProfileSection.values.length,
      vsync: this,
      initialIndex: widget.initialSection.index,
    );
    _tabLoadingController = ProfileTabLoadingController(
      isMounted: () => mounted,
      currentIndex: () => _tabController.index,
      updateState: (update) => setState(update),
    );
    _isHomeTabMediaVisible = widget.initialSection == ProfileSection.home;
    _isGalleryTabActive = widget.initialSection == ProfileSection.gallery;
    _galleryDetailFetchesActive = ValueNotifier<bool>(_isGalleryTabActive);
    appAnalytics.logScreen(
      UserProfileScreen._screenFor(
        ProfileSection.values[_tabController.index],
      ),
    );
    _backSwipeAnimationController = AnimationController(vsync: this)
      ..addListener(_onBackSwipeAnimationTick)
      ..addStatusListener(_onBackSwipeAnimationStatusChanged);

    // Load only the initial tab immediately; others will load after "settling".
    _tabLoadingController.loadInitialSection(
      ProfileSection.values[_tabController.index],
    );

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        // Cancel any pending lazy-load while the tab is still animating/dragging.
        _tabLoadingController.cancelPendingLoad();
        return;
      }

      // Tab finished changing; schedule lazy-load for the final tab.
      _tabLoadingController.scheduleLoad(_tabController.index);
      _updateMoveUpFabLift();

      if (_previousIndex != _tabController.index) {
        appAnalytics.logScreen(
          UserProfileScreen._screenFor(
            ProfileSection.values[_tabController.index],
          ),
        );
        final double appBarHeight =
            sliverAppBarExpandedHeight - sliverAppBarMinHeight;
        final double targetOffset =
            appBarHeight + collapsibleHeaderMaxHeight - 24;

        if (_scrollController.hasClients &&
            _scrollController.offset >= targetOffset) {
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        _previousIndex = _tabController.index;
      }
    });

    _initAsyncFetch();
  }

  @override
  void didPushNext() {
    if (_suppressNextRouteDetach) {
      return;
    }
    _isProfileRouteCurrent = false;
    _updateGalleryDetailFetchActivity();
    _setRouteWebViewDetached(true);
  }

  @override
  void didPopNext() {
    _isProfileRouteCurrent = true;
    _updateGalleryDetailFetchActivity();
    _setRouteWebViewDetached(false);
  }

  @override
  bool get routeWebViewDetached => _isProfileWebViewDetached;

  @override
  void setRouteWebViewDetached(bool detached) {
    _setRouteWebViewDetached(detached);
  }

  void _setRouteWebViewDetached(bool detached) {
    if (_isProfileWebViewDetached == detached) {
      return;
    }
    _isProfileWebViewDetached = detached;
    if (detached) {
      unawaited(_webViewKey.currentState?.pauseWebView() ?? Future.value());
    } else {
      unawaited(_webViewKey.currentState?.resumeWebView() ?? Future.value());
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _onProfileScroll() {
    if (_webViewScrollOptimizationEnabled) {
      _pauseWebViewDuringScroll();
    }
    _onScrollForMoveUpFab();
  }

  bool _handleProfileScrollNotification(ScrollNotification notification) {
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
    final state = _webViewKey.currentState;
    if (state == null) {
      return;
    }
    if (!_isWebViewPausedForScroll) {
      _isWebViewPausedForScroll = true;
      unawaited(
        state.pauseWebView(
          reason: UserDescriptionWebViewPauseReason.scrolling,
        ),
      );
    }
    _scrollWebViewResumeTimer?.cancel();
    _scrollWebViewResumeTimer = Timer(_scrollWebViewResumeDelay, () {
      final currentState = _webViewKey.currentState;
      _isWebViewPausedForScroll = false;
      if (currentState == null) {
        return;
      }
      unawaited(
        currentState.resumeWebView(
          reason: UserDescriptionWebViewPauseReason.scrolling,
        ),
      );
    });
  }

  void _onScrollForMoveUpFab() {
    final bool shouldShow =
        _scrollController.hasClients && _scrollController.offset > 140.0;
    if (_showMoveUpFab.value != shouldShow) {
      _showMoveUpFab.value = shouldShow;
    }
  }

  void _onBulkSelectionLayoutChanged(
    ProfileSection section,
    bool active,
    double barHeight,
  ) {
    if (active) {
      _bulkSelectionActiveSections.add(section);
      if (barHeight > 0) {
        _bulkSelectionBarHeights[section] = barHeight;
      }
    } else {
      _bulkSelectionActiveSections.remove(section);
      _bulkSelectionBarHeights.remove(section);
    }
    _updateMoveUpFabLift();
  }

  void _updateMoveUpFabLift() {
    final section = ProfileSection.values[_tabController.index];
    final active = _bulkSelectionActiveSections.contains(section);
    final barHeight = _bulkSelectionBarHeights[section] ?? 0.0;
    final lift = active && barHeight > 0
        ? max(
            0.0,
            barHeight +
                _bulkSelectionMoveUpGap -
                _moveUpFabDefaultBottomSpacing,
          )
        : 0.0;
    if ((_moveUpFabLift.value - lift).abs() > 0.1) {
      _moveUpFabLift.value = lift;
    }
  }

  Future<void> _initAsyncFetch() async {
    await _loadSfwEnabled();
    if (!mounted) {
      return;
    }
    await _fetchUserProfile();
  }

  void _handleHomeTabMediaVisibility(bool visible) {
    if (_isHomeTabMediaVisible == visible) {
      return;
    }
    _isHomeTabMediaVisible = visible;
    final state = _webViewKey.currentState;
    if (state == null) {
      return;
    }
    if (visible) {
      unawaited(
        state.resumeGifPlayback(
          reason: UserDescriptionWebViewPauseReason.tab,
        ),
      );
    } else {
      unawaited(
        state.pauseGifPlayback(
          reason: UserDescriptionWebViewPauseReason.tab,
        ),
      );
    }
  }

  void _handleGalleryTabActivity(bool active) {
    if (_isGalleryTabActive == active) return;
    _isGalleryTabActive = active;
    _updateGalleryDetailFetchActivity();
  }

  void _updateGalleryDetailFetchActivity() {
    _galleryDetailFetchesActive.value =
        _isGalleryTabActive && _isProfileRouteCurrent;
  }

  void _resumeTopMediaForMoveUp() {
    _moveUpMediaProactiveTimer?.cancel();
    _moveUpMediaProactive.value = true;
    _moveUpMediaProactiveTimer = Timer(
      const Duration(milliseconds: 450),
      () => _moveUpMediaProactive.value = false,
    );
    _avatarMediaVisibilityKey.currentState?.resumeProactively();
    _descriptionMediaVisibilityKey.currentState?.resumeProactively();
    unawaited(
      _webViewKey.currentState?.resumeGifPlayback(
            reason: UserDescriptionWebViewPauseReason.visibility,
          ) ??
          Future<void>.value(),
    );
  }

  Future<bool> _attemptCloseProfileScreen({
    bool resetBackSwipeOffset = true,
  }) async {
    await (_webViewKey.currentState?.pauseWebView() ?? Future.value());
    if (resetBackSwipeOffset) {
      _resetEdgeBackSwipe();
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (!mounted) {
      return false;
    }
    return Navigator.maybePop(context);
  }

  void _closeProfileScreen() {
    _attemptCloseProfileScreen();
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
    final didPop =
        await _attemptCloseProfileScreen(resetBackSwipeOffset: false);
    if (!didPop && mounted) {
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

  void _handleEdgeBackSwipeStart(DragStartDetails details) {
    if (!(Platform.isAndroid || Platform.isIOS) || _isShoutSelectionMode) {
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

  void _handleEdgeBackSwipePointerDown(PointerDownEvent event) {
    if (!(Platform.isAndroid || Platform.isIOS) || _isShoutSelectionMode) {
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

  IconData _getIconForSection(ProfileSection section) {
    switch (section) {
      case ProfileSection.home:
        return Icons.home_rounded;
      case ProfileSection.gallery:
        return Icons.photo;
      case ProfileSection.scraps:
        return Icons.collections_bookmark;
      case ProfileSection.favs:
        return Icons.favorite;
      case ProfileSection.journals:
        return Icons.book;
    }
  }

  String _getTabTitle(ProfileSection section) {
    switch (section) {
      case ProfileSection.home:
        return 'Home';
      case ProfileSection.gallery:
        return 'Gallery';
      case ProfileSection.scraps:
        return 'Scraps';
      case ProfileSection.favs:
        return 'Favs';
      case ProfileSection.journals:
        return 'Journals';
    }
  }

  Future<WatchUnwatchResult> _sendWatchUnwatchRequest(String urlPath,
      {required bool shouldWatch}) async {
    final result = await _profileRepository.updateWatchState(
      urlPath: urlPath,
      shouldWatch: shouldWatch,
      sfwEnabled: _profileController.sfwEnabled,
    );

    if (result.success) {
      debugPrint('${shouldWatch ? 'Watch' : 'Unwatch'} action successful.');
      _profileController.setWatching(shouldWatch);
    } else if (result.error != null) {
      debugPrint(
          'Error during ${shouldWatch ? 'watch' : 'unwatch'}: ${result.error}');
    } else {
      debugPrint(
          'Failed to ${shouldWatch ? 'watch' : 'unwatch'}. Status code: ${result.statusCode}');
    }
    return result;
  }

  void _showWatchOutcomeSnackBar(WatchUnwatchResult result,
      {required bool shouldWatch}) {
    final messenger = rootMessengerKey.currentState;
    if (messenger == null) return;
    if (result.missingCookies) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please log in to perform this action.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    } else if (result.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            shouldWatch
                ? 'Now watching ${_profileController.username}'
                : 'Stopped watching ${_profileController.username}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (result.error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleWatchButtonPressed() async {
    if (_watchRequestInFlight.value) return;
    _watchRequestInFlight.value = true;
    WatchUnwatchResult? result;
    final shouldWatch = !_profileController.isWatching;
    try {
      if (_profileController.isWatching) {
        if (_profileController.unwatchLink == null) {
          debugPrint('Unwatch link not available.');
          return;
        }
        result = await _sendWatchUnwatchRequest(
          _profileController.unwatchLink!,
          shouldWatch: false,
        );
        await _fetchUserProfile();
      } else {
        if (_profileController.watchLink == null) {
          debugPrint('Watch link not available.');
          return;
        }
        result = await _sendWatchUnwatchRequest(
          _profileController.watchLink!,
          shouldWatch: true,
        );
        await _fetchUserProfile();
      }
    } finally {
      if (mounted) {
        _watchRequestInFlight.value = false;
      }
    }
    _showWatchOutcomeSnackBar(result, shouldWatch: shouldWatch);
  }

  void _toggleShoutSelectionMode() {
    _shoutSelectionController.toggleMode();
    if (mounted) {
      setState(() {});
    }
  }

  void exitShoutSelectionMode() {
    if (!_isShoutSelectionMode) {
      return;
    }
    _shoutSelectionController.exitSelectionMode();
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleShoutSelection(Shout shout) {
    if (!_isShoutSelectionMode) {
      return;
    }

    _shoutSelectionController.toggle(shout);
  }

  Future<bool> _showDeleteShoutsDialog(
    List<Shout> shoutsToDelete, {
    bool ownShoutOnOtherProfile = false,
  }) {
    return showProfileDeleteShoutsDialog(
      shoutsToDelete,
      context: context,
      ownShoutOnOtherProfile: ownShoutOnOtherProfile,
    );
  }

  Future<void> _confirmDeleteSelectedShouts() async {
    if (!_profileController.isOwnProfile ||
        _isDeletingSelectedShouts.value) {
      return;
    }

    final selectedShouts = _shoutSelectionController.selectedShouts(
      _profileController.shouts,
    );
    if (selectedShouts.isEmpty) {
      return;
    }

    final confirmed = await _showDeleteShoutsDialog(selectedShouts);
    if (!confirmed) {
      return;
    }

    await _deleteShouts(selectedShouts);
  }

  Future<void> _confirmDeleteShout(int index, Shout shout) async {
    final canDeleteOwnShoutOnOtherProfile =
        !_profileController.isOwnProfile && shout.ownShoutDeleteUrl != null;
    if (!_profileController.isOwnProfile &&
        !canDeleteOwnShoutOnOtherProfile) {
      return;
    }

    final confirmed = await _showDeleteShoutsDialog(
      [shout],
      ownShoutOnOtherProfile: canDeleteOwnShoutOnOtherProfile,
    );
    if (confirmed) {
      if (canDeleteOwnShoutOnOtherProfile) {
        await _deleteOwnShoutFromOtherProfile(shout);
      } else {
        await _deleteShout(index, shout);
      }
    }
  }

  Future<void> _deleteOwnShoutFromOtherProfile(Shout shout) async {
    if (_isDeletingSelectedShouts.value || shout.ownShoutDeleteUrl == null) {
      return;
    }

    final loadedProfilePage = _profileController.currentShoutPage;
    _isDeletingSelectedShouts.value = true;

    try {
      final result = await _profileRepository.deleteOwnShoutFromProfile(
        shout: shout,
        sanitizedProfileUsername: _profileController.sanitizedUsername,
        sfwEnabled: _profileController.sfwEnabled,
      );
      if (!mounted) return;

      if (result.missingCookies) {
        showAppSnackBar(
          context,
          'Please log in to perform this action.',
          backgroundColor: Colors.red,
        );
      } else if (result.success) {
        showAppSnackBar(
          context,
          'Shout deleted.',
          backgroundColor: Colors.green,
        );
        await _fetchUserProfile();
        await _restoreLoadedShoutPages(loadedProfilePage);
      } else if (result.error != null) {
        showAppSnackBar(
          context,
          'The delete result could not be confirmed. Refresh the profile before trying again.',
          backgroundColor: Colors.red,
        );
      } else {
        showAppSnackBar(
          context,
          'Failed to delete shout.',
          backgroundColor: Colors.red,
        );
      }
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'The delete result could not be confirmed. Refresh the profile before trying again.',
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) {
        _isDeletingSelectedShouts.value = false;
      }
    }
  }

  Future<void> _deleteShout(int _, Shout shout) async {
    await _deleteShouts([shout]);
  }

  Future<void> _deleteShouts(List<Shout> shoutsToDelete) async {
    if (shoutsToDelete.isEmpty || _isDeletingSelectedShouts.value) {
      return;
    }

    final loadedProfilePage = _profileController.currentShoutPage;

    _isDeletingSelectedShouts.value = true;

    try {
      final deletionResult = await _profileRepository.deleteShouts(
        shouts: shoutsToDelete,
        sfwEnabled: _profileController.sfwEnabled,
      );

      if (!mounted) return;
      if (deletionResult.status ==
          UserProfileShoutDeletionStatus.unmatched) {
        showAppSnackBar(
          context,
          "Failed to match one or more selected shouts on the controls page.",
          backgroundColor: Colors.red,
        );
        return;
      }

      if (deletionResult.status ==
          UserProfileShoutDeletionStatus.missingCookies) {
        showAppSnackBar(context, "Please log in to perform this action.",
            backgroundColor: Colors.red);
      } else if (deletionResult.status ==
          UserProfileShoutDeletionStatus.success) {
        final deletedCount = shoutsToDelete.length;
        showAppSnackBar(
          context,
          deletedCount == 1
              ? "Shout deleted."
              : "$deletedCount shouts deleted.",
          backgroundColor: Colors.green,
        );
        exitShoutSelectionMode();
        await _fetchUserProfile();
        await _restoreLoadedShoutPages(loadedProfilePage);
      } else if (deletionResult.status ==
          UserProfileShoutDeletionStatus.partialFailure) {
        showAppSnackBar(
          context,
          "Some selected shouts were deleted, but one page failed.",
          backgroundColor: Colors.red,
        );
        exitShoutSelectionMode();
        await _fetchUserProfile();
        await _restoreLoadedShoutPages(loadedProfilePage);
      } else if (deletionResult.error != null) {
        showAppSnackBar(context, "Error: ${deletionResult.error}",
            backgroundColor: Colors.red);
      } else {
        showAppSnackBar(context, "Failed to delete shout.",
            backgroundColor: Colors.red);
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, "Error: $e", backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        _isDeletingSelectedShouts.value = false;
      }
    }
  }

  Future<void> _restoreLoadedShoutPages(int targetPage) async {
    while (mounted &&
        _profileController.currentShoutPage < targetPage &&
        _profileController.currentShoutPage <
            _profileController.totalShoutPages) {
      await _loadMoreShouts();
    }
  }

  Future<void> _launchURL(String url) async {
    await handleFALink(context, url);
  }

  /// Handles FA links inside HTML/description, matching the legacy inline logic.
  Future<void> _handleFALink(BuildContext context, String url) async {
    final target = matchFALink(url);

    switch (target.type) {
      case FALinkTargetType.gallery:
        exitShoutSelectionMode();
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
        exitShoutSelectionMode();
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
        exitShoutSelectionMode();
        Navigator.push(
          context,
          UserProfileScreen.route(
            nickname: target.username!,
            initialSection: ProfileSection.scraps,
          ),
        );
        return;
      case FALinkTargetType.user:
        exitShoutSelectionMode();
        Navigator.push(
          context,
          UserProfileScreen.route(nickname: target.username!),
        );
        return;
      case FALinkTargetType.journalUser:
        exitShoutSelectionMode();
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
        await handleExternalLink(context, url);
        return;
    }
  }

  /// Fetches the user's profile data from FurAffinity.
  Future<void> _fetchUserProfile({bool afterEdit = false}) async {
    try {
      final previousDescription = _profileController.userDescription;
      final previousMediaUrls = <String?>[
        _profileController.profileImageUrl,
        _profileController.profileBannerUrl,
      ];
      if (afterEdit) await _evictProfileMedia(previousMediaUrls);
      final result = await _profileController.loadProfile(widget.nickname);
      if (afterEdit) {
        await _evictProfileMedia([
          result.parsed.profileImageUrl,
          result.parsed.profileBannerUrl,
        ]);
      }
      if (!mounted) return;

      final rebuildDescription =
          afterEdit || previousDescription != result.parsed.userDescription;
      final wasWebViewLoaded = _webViewLoaded.value;
      setState(() {
        if (rebuildDescription) {
          _webViewKey = GlobalKey<UserDescriptionWebViewState>();
        }
        if (afterEdit) _profileMediaRevision++;
      });
      _webViewLoaded.value = result.shouldShowDescription
          ? (rebuildDescription ? false : wasWebViewLoaded)
          : true;
      _shoutSelectionController.reconcile(_profileController.shouts);
      _shoutsRevision.value++;
      _updateProfileAvatarTransparency(result.parsed.profileImageUrl);

      debugPrint(
          "Block/Unblock Link: ${_profileController.blockLink} / ${_profileController.unblockLink}");
      debugPrint(
          "Watch/Unwatch Link: ${_profileController.watchLink} / ${_profileController.unwatchLink}");
      debugPrint("isBlocked: ${_profileController.isBlocked}");
    } on StateError catch (e) {
      if (mounted) setState(() {});
      debugPrint(e.toString());
    } catch (e) {
      if (mounted) setState(() {});
      debugPrint("An error occurred while fetching profile: $e");
    }
  }

  Future<void> _evictProfileMedia(Iterable<String?> urls) async {
    for (final url in urls) {
      if (url == null || url.trim().isEmpty) continue;
      try {
        final provider = await faNetworkImageProvider(url);
        await provider.evict();
      } catch (_) {}
    }
  }

  void switchToGalleryTab() {
    _tabController.animateTo(ProfileSection.gallery.index);
  }

  Future<void> _loadMoreShouts() async {
    if (_isLoadingMoreShouts.value ||
        _profileController.currentShoutPage >=
            _profileController.totalShoutPages) {
      debugPrint(
          "Cannot load more shouts. Loading: ${_isLoadingMoreShouts.value}, Current: ${_profileController.currentShoutPage}, Total: ${_profileController.totalShoutPages}");
      return;
    }

    _isLoadingMoreShouts.value = true;

    try {
      final nextPage = _profileController.currentShoutPage + 1;
      final payload = await _profileRepository.loadAdditionalShouts(
        sanitizedUsername: _profileController.sanitizedUsername,
        shoutPaginationKey: _profileController.shoutPaginationKey,
        nextPage: nextPage,
        sfwEnabled: _profileController.sfwEnabled,
        existingShoutIds:
            _profileController.shouts.map((shout) => shout.id).toSet(),
      );

      if (!mounted) return;
      if (payload == null) {
        debugPrint("Missing shout pagination key; cannot load more shouts.");
        return;
      }

      _profileController.addShouts(payload);
      _shoutSelectionController.reconcile(_profileController.shouts);
      _shoutsRevision.value++;
    } catch (e) {
      debugPrint('Error loading more shouts: $e');
      if (!mounted) return;
      showAppSnackBar(context, 'Failed to load more shouts',
          backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        _isLoadingMoreShouts.value = false;
      }
    }
  }

  Widget buildAnimatedAvatar(
    double offset,
    Widget avatarChild, {
    required bool animationEnabled,
  }) {
    return buildProfileAnimatedAvatar(
      offset,
      avatarChild,
      animationEnabled: animationEnabled,
      context: context,
    );
  }

  void _updateProfileAvatarTransparency(String? imageUrl) {
    final String? trimmedUrl = imageUrl?.trim();
    final int generation = ++_profileAvatarTransparencyCheckGeneration;
    if (trimmedUrl == null || trimmedUrl.isEmpty) {
      _profileAvatarTransparencyCheckedUrl = null;
      if (!_profileAvatarBorderVisible.value && mounted) {
        _profileAvatarBorderVisible.value = true;
      }
      return;
    }
    if (_profileAvatarTransparencyCheckedUrl == trimmedUrl) {
      return;
    }
    _profileAvatarTransparencyCheckedUrl = trimmedUrl;
    if (_profileAvatarBorderVisible.value && mounted) {
      _profileAvatarBorderVisible.value = false;
    }

    faNetworkImageProvider(trimmedUrl).then((provider) {
      if (!mounted ||
          generation != _profileAvatarTransparencyCheckGeneration ||
          _profileAvatarTransparencyCheckedUrl != trimmedUrl) {
        return;
      }
      final ImageStream stream = provider.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo imageInfo, bool synchronousCall) async {
          stream.removeListener(listener);
          final bool hasTransparentEdge =
              await _avatarTransparencyDetector
                  .hasTransparentEdge(imageInfo.image);
          if (!mounted ||
              generation != _profileAvatarTransparencyCheckGeneration ||
              _profileAvatarTransparencyCheckedUrl != trimmedUrl) {
            return;
          }
          final bool shouldShowBorder = !hasTransparentEdge;
          if (_profileAvatarBorderVisible.value != shouldShowBorder) {
            _profileAvatarBorderVisible.value = shouldShowBorder;
          }
        },
        onError: (Object error, StackTrace? stackTrace) {
          stream.removeListener(listener);
          if (!mounted ||
              generation != _profileAvatarTransparencyCheckGeneration ||
              _profileAvatarTransparencyCheckedUrl != trimmedUrl) {
            return;
          }
          if (!_profileAvatarBorderVisible.value) {
            _profileAvatarBorderVisible.value = true;
          }
        },
      );
      stream.addListener(listener);
    });
  }

  Widget buildAvatarImage() {
    return buildProfileAvatarImage(
      profileImageUrl: _profileController.profileImageUrl,
      profileMediaRevision: _profileMediaRevision,
      avatarMediaVisibilityKey: _avatarMediaVisibilityKey,
      profileAvatarBorderVisible: _profileAvatarBorderVisible,
    );
  }

  final ValueNotifier<GlobalKey> _profileNameRowKey =
      ValueNotifier<GlobalKey>(GlobalKey());

  void _clearProfileNameSelection() {
    _profileNameRowKey.value = GlobalKey();
  }

  void _copyProfileLinkToClipboard() {
    final profileLink =
        'https://www.furaffinity.net/user/${_profileController.sanitizedUsername}/';
    Clipboard.setData(ClipboardData(text: profileLink)).then((_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Copied profile link!',
          backgroundColor: Colors.green);
    }).catchError((error) {
      debugPrint('Failed to copy profile link: $error');
      if (!mounted) return;
      showAppSnackBar(context, 'Failed to copy profile link.',
          backgroundColor: Colors.red);
    });
  }

  Widget _buildProfileHeaderNameRow(GlobalKey profileNameRowKey) {
    return buildProfileHeaderNameRow(
      profileNameRowKey,
      profileController: _profileController,
      clearProfileNameSelection: _clearProfileNameSelection,
    );
  }

  Future<void> _sendBlockUnblockRequest(
    String urlOrPath,
    String keyValue, {
    required bool shouldBlock,
    required bool usePost,
  }) async {
    final result = await _profileRepository.updateBlockState(
      urlOrPath: urlOrPath,
      keyValue: keyValue,
      shouldBlock: shouldBlock,
      usePost: usePost,
      sfwEnabled: _profileController.sfwEnabled,
      sanitizedUsername: _profileController.sanitizedUsername,
    );

    if (!mounted) return;
    if (result.missingCookies) {
      showAppSnackBar(
        context,
        'Please log in to perform this action.',
        backgroundColor: Colors.red,
      );
      return;
    }

    if (result.success) {
      await _fetchUserProfile();
      if (!mounted) return;
      showAppSnackBar(
        context,
        shouldBlock ? 'Author blocked' : 'Author unblocked',
        backgroundColor: Colors.green,
      );
    } else if (result.error != null) {
      showAppSnackBar(
        context,
        'An error occurred while trying to ${shouldBlock ? 'block' : 'unblock'} author.',
        backgroundColor: Colors.red,
      );
    } else {
      showAppSnackBar(
        context,
        'Failed to ${shouldBlock ? 'block' : 'unblock'} author.',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _handleBlockUnblock() async {
    if (_profileController.isBlocked) {
      if (_profileController.unblockLink == null) {
        showAppSnackBar(
          context,
          'Cannot unblock author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }
      final key = extractBlockUnblockKey(_profileController.unblockLink!);

      if (key == null || key.isEmpty) {
        showAppSnackBar(
          context,
          'Cannot unblock author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }

      await _sendBlockUnblockRequest(
        _profileController.unblockLink!,
        key,
        shouldBlock: false,
        usePost: _profileController.unblockUsesPost,
      );
    } else {
      if (_profileController.blockLink == null) {
        showAppSnackBar(
          context,
          'Cannot block author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }

      final key = extractBlockUnblockKey(_profileController.blockLink!);

      if (key == null || key.isEmpty) {
        showAppSnackBar(
          context,
          'Cannot block author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }

      await _sendBlockUnblockRequest(
        _profileController.blockLink!,
        key,
        shouldBlock: true,
        usePost: _profileController.blockUsesPost,
      );
    }
  }

  Widget _buildDeleteSelectedShoutsFab() {
    return Positioned(
      left: 16.0,
      bottom: 16.0,
      child: ValueListenableBuilder<int>(
        valueListenable: _shoutSelectionController.selectedCount,
        builder: (context, selectedCount, child) {
          final showDeleteSelectedFab = !_profileController.isLoading &&
              _profileController.isOwnProfile &&
              _isShoutSelectionMode &&
              selectedCount > 0;
          return IgnorePointer(
            ignoring: !showDeleteSelectedFab,
            child: ExcludeSemantics(
              excluding: !showDeleteSelectedFab,
              child: AnimatedOpacity(
                opacity: showDeleteSelectedFab ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 210),
                curve: Curves.easeInOut,
                child: AnimatedScale(
                  scale: showDeleteSelectedFab ? 1.0 : 0.92,
                  duration: const Duration(milliseconds: 210),
                  curve: Curves.easeInOut,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isDeletingSelectedShouts,
                    builder: (context, isDeleting, child) {
                      return FloatingActionButton(
                        heroTag: null,
                        onPressed:
                            isDeleting ? null : _confirmDeleteSelectedShouts,
                        backgroundColor: Colors.red,
                        tooltip: 'Delete Selected Shouts',
                        child: isDeleting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.delete, color: Colors.white),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMoveUpFab() {
    return FloatingActionButton(
      onPressed: () {
        _resumeTopMediaForMoveUp();
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      },
      backgroundColor: const Color(0xFFE09321),
      tooltip: 'Scroll to Top',
      child: const Icon(
        Icons.arrow_upward,
        color: Colors.white,
      ),
    );
  }

  /// Builds the main UI of the screen with unified scrolling.
  @override
  Widget build(BuildContext context) {
    const double avatarLeft = 16.0;
    const double avatarWidth = 90.0;
    const double marginBetweenAvatarAndText = 0.0;
    final double textLeftPadding =
        avatarLeft + avatarWidth + marginBetweenAvatarAndText;
    final registrationTimeFormat =
        context.select<TimeDisplaySettingsProvider, TimeDisplayFormat>(
      (settings) => settings.formatFor(
        TimeDisplayOccasion.profileRegistration,
      ),
    );
    final platformViews = WidgetsBinding.instance.platformDispatcher.views;
    final baseView =
        platformViews.isNotEmpty ? platformViews.first : View.of(context);
    final fixedTextScaleMediaQuery = MediaQueryData.fromView(baseView)
        .copyWith(textScaler: TextScaler.linear(1.0));
    return ExcludeSemantics(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Color(0xCC000000),
          systemNavigationBarIconBrightness: Brightness.light,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        child: PopScope(
          canPop: !_isShoutSelectionMode,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _isShoutSelectionMode) {
              _toggleShoutSelectionMode();
            }
          },
          child: TickerMode(
              enabled: !_isProfileWebViewDetached,
              child: _buildEdgeBackSwipeTransition(
                child: Scaffold(
                  backgroundColor: Colors.black,
                  body: SafeArea(
                    top: false,
                    child: Stack(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => _clearProfileNameSelection(),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _handleProfileScrollNotification,
                            child: NestedScrollView(
                              key: ValueKey<int>(_iosScrollRecoveryKey),
                              controller: _scrollController,
                              physics: Platform.isIOS
                                  ? const ClampingScrollPhysics()
                                  : null,
                              headerSliverBuilder:
                                  (context, innerBoxIsScrolled) => [
                                SliverAppBar(
                                  centerTitle: false,
                                  leading: IconButton(
                                    icon: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Positioned(
                                            left: 1,
                                            child: Icon(Icons.arrow_back,
                                                size: 24,
                                                color: Color(0xFF111111))),
                                        Positioned(
                                            right: 1,
                                            child: Icon(Icons.arrow_back,
                                                size: 24,
                                                color: Color(0xFF111111))),
                                        Positioned(
                                            top: 1,
                                            child: Icon(Icons.arrow_back,
                                                size: 24,
                                                color: Color(0xFF111111))),
                                        Positioned(
                                            bottom: 1,
                                            child: Icon(Icons.arrow_back,
                                                size: 24,
                                                color: Color(0xFF111111))),
                                        Icon(Icons.arrow_back,
                                            size: 24, color: Colors.white),
                                      ],
                                    ),
                                    onPressed: _closeProfileScreen,
                                  ),
                                  title: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Stack(
                                        children: [
                                          // Stroked text as outline
                                          Text(
                                            _profileController.symbolUsername ??
                                                'Profile',
                                            style: TextStyle(
                                              fontSize: 18.0,
                                              fontWeight: FontWeight.bold,
                                              foreground: Paint()
                                                ..style = PaintingStyle.stroke
                                                ..strokeWidth = 2
                                                ..color = Color(0xFF111111),
                                            ),
                                          ),
                                          // Filled text on top
                                          Text(
                                            _profileController.symbolUsername ??
                                                'Profile',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18.0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_profileController.symbolUsername !=
                                              null &&
                                          _profileController.symbolUsername!
                                              .startsWith('!'))
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8.0),
                                          child: Text(
                                            "USER BANNED",
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 18.0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  expandedHeight: sliverAppBarExpandedHeight,
                                  pinned: true,
                                  floating: false,
                                  snap: false,
                                  backgroundColor: Colors.black.withValues(
                                    alpha: (_scrollController.hasClients &&
                                            _scrollController.offset > 50)
                                        ? (_scrollController.offset / 200)
                                            .clamp(0.0, 1.0)
                                        : 0.0,
                                  ),
                                  actions: [
                                    PopupMenuButton<String>(
                                      position: PopupMenuPosition.under,
                                      offset: const Offset(0, 8),
                                      icon: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Positioned(
                                              left: 1,
                                              child: Icon(Icons.more_vert,
                                                  size: 24,
                                                  color: Color(0xFF111111))),
                                          Positioned(
                                              right: 1,
                                              child: Icon(Icons.more_vert,
                                                  size: 24,
                                                  color: Color(0xFF111111))),
                                          Positioned(
                                              top: 1,
                                              child: Icon(Icons.more_vert,
                                                  size: 24,
                                                  color: Color(0xFF111111))),
                                          Positioned(
                                              bottom: 1,
                                              child: Icon(Icons.more_vert,
                                                  size: 24,
                                                  color: Color(0xFF111111))),
                                          Icon(Icons.more_vert,
                                              size: 24, color: Colors.white),
                                        ],
                                      ),
                                      onOpened: () {
                                        _suppressNextRouteDetach = true;
                                      },
                                      onCanceled: () {
                                        _suppressNextRouteDetach = false;
                                      },
                                      onSelected: (selected) async {
                                        _suppressNextRouteDetach = false;
                                        switch (selected) {
                                          case 'report':
                                            launchUrlString(
                                                'https://www.furaffinity.net/controls/troubletickets/');
                                            break;
                                          case 'block_unblock':
                                            if (!_profileController
                                                .isOwnProfile) {
                                              await _handleBlockUnblock();
                                            }
                                            break;
                                          case 'copy_link':
                                            _copyProfileLinkToClipboard();
                                            break;
                                          case 'translate':
                                            await _openProfileTranslation();
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem<String>(
                                          value: 'report',
                                          child: Text('Report'),
                                        ),
                                        if (!_profileController.isOwnProfile)
                                          PopupMenuItem<String>(
                                            value: 'block_unblock',
                                            child: Text(_profileController
                                                    .isBlocked
                                                ? 'Unblock author'
                                                : 'Block author'),
                                          ),
                                        const PopupMenuItem<String>(
                                          value: 'copy_link',
                                          child: Text('Copy link'),
                                        ),
                                        const PopupMenuItem<String>(
                                          value: 'translate',
                                          child: Text('Translate'),
                                        ),
                                      ],
                                    ),
                                  ],
                                  flexibleSpace: LayoutBuilder(
                                    builder: (context, _) {
                                      final Widget staticBannerLayers =
                                          Positioned.fill(
                                        key: const ValueKey<String>(
                                            'profileBannerLayer'),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            ProfileBannerHeader(
                                              imageUrl: _profileController
                                                      .profileBannerUrl ??
                                                  'https://d.furaffinity.net/media/banners/modern/fa-banner-summer.jpg',
                                              mediaRevision:
                                                  _profileMediaRevision,
                                              expandedHeight:
                                                  sliverAppBarExpandedHeight,
                                            ),
                                            ColoredBox(
                                              color: Colors.black
                                                  .withValues(alpha: 0.15),
                                            ),
                                          ],
                                        ),
                                      );

                                      return AnimatedBuilder(
                                        animation: Listenable.merge([
                                          _scrollController,
                                          _moveUpMediaProactive,
                                        ]),
                                        child: buildAvatarImage(),
                                        builder: (context, child) {
                                          final double offset =
                                              _scrollController.hasClients
                                                  ? _scrollController.offset
                                                  : 0.0;
                                          final Widget avatar =
                                              buildAnimatedAvatar(
                                            offset,
                                            child ?? const SizedBox.shrink(),
                                            animationEnabled: offset <
                                                    _profileAvatarBehindBannerStart ||
                                                _moveUpMediaProactive.value,
                                          );
                                          final bool avatarBehindBanner =
                                              offset >=
                                                  _profileAvatarBehindBannerStart;

                                          return Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              if (avatarBehindBanner) avatar,
                                              staticBannerLayers,
                                              if (!avatarBehindBanner) avatar,
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                                buildProfileDetailsHeader(
                                  context: context,
                                  profileController: _profileController,
                                  fixedTextScaleMediaQuery: fixedTextScaleMediaQuery,
                                  textLeftPadding: textLeftPadding,
                                  registrationTimeFormat: registrationTimeFormat,
                                  profileNameRowKey: _profileNameRowKey,
                                  buildHeaderNameRow: _buildProfileHeaderNameRow,
                                  watchRequestInFlight: _watchRequestInFlight,
                                  onEditProfile: _showEditProfileDialog,
                                  onWatch: _handleWatchButtonPressed,
                                ),
                                SliverOverlapAbsorber(
                                  handle: NestedScrollView
                                      .sliverOverlapAbsorberHandleFor(context),
                                  sliver: SliverPersistentHeader(
                                    pinned: true,
                                    delegate: NavigationSliderSliverDelegate(
                                      minHeight: navigationSliderHeight + 1.0,
                                      maxHeight: navigationSliderHeight + 1.0,
                                      child: NavigationSlider(
                                        sections: ProfileSection.values,
                                        tabController: _tabController,
                                        getTabTitle: _getTabTitle,
                                        getIconForSection: _getIconForSection,
                                        onTabTapped:
                                            (index, isAlreadySelected) {
                                          if (isAlreadySelected) {
                                            _resumeTopMediaForMoveUp();
                                            _scrollController.animateTo(
                                              0.0,
                                              duration: const Duration(
                                                  milliseconds: 300),
                                              curve: Curves.easeOut,
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              body: TabBarView(
                                controller: _tabController,
                                children: ProfileSection.values.map((section) {
                                  return ProfileTabScrollScope(
                                    key: ValueKey(section),
                                    tabController: _tabController,
                                    tabIndex: section.index,
                                    recoveryKey: _iosScrollRecoveryKey,
                                    onActiveChanged:
                                        section == ProfileSection.gallery
                                            ? _handleGalleryTabActivity
                                            : null,
                                    onMediaVisibilityChanged:
                                        section == ProfileSection.home
                                            ? _handleHomeTabMediaVisibility
                                            : null,
                                    child: _buildLazySection(section),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _tabController,
                          builder: (context, child) {
                            return ValueListenableBuilder<bool>(
                              valueListenable: _webViewLoaded,
                              builder: (context, webViewLoaded, child) {
                                final needsDescriptionLoad =
                                    _profileController.hasRealUserProfile &&
                                        _profileController.userDescription !=
                                            null;
                                final showLoadingIndicator =
                                    _profileController.isLoading ||
                                        (needsDescriptionLoad &&
                                            !webViewLoaded &&
                                            _tabController.index ==
                                                ProfileSection.home.index);
                                if (!showLoadingIndicator) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  color: Colors.black.withValues(alpha: 1.0),
                                  child: const Center(
                                    child: PulsatingLoadingIndicator(
                                      size: 88.0,
                                      assetPath: 'assets/icons/fathemed.png',
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        _buildEdgeBackSwipeOverlay(),
                        _buildDeleteSelectedShoutsFab(),
                      ],
                    ),
                  ),
                  floatingActionButton: !_profileController.isLoading
                      ? ValueListenableBuilder<double>(
                          valueListenable: _moveUpFabLift,
                          builder: (context, lift, child) {
                            return AnimatedPadding(
                              padding: EdgeInsets.only(bottom: lift),
                              duration: const Duration(milliseconds: 210),
                              curve: Curves.easeInOut,
                              child: child,
                            );
                          },
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _showMoveUpFab,
                            builder: (context, showFab, child) {
                              return IgnorePointer(
                                ignoring: !showFab,
                                child: ExcludeSemantics(
                                  excluding: !showFab,
                                  child: AnimatedOpacity(
                                    opacity: showFab ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 210),
                                    curve: Curves.easeInOut,
                                    child: AnimatedScale(
                                      scale: showFab ? 1.0 : 0.92,
                                      duration:
                                          const Duration(milliseconds: 210),
                                      curve: Curves.easeInOut,
                                      child: child,
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: _buildMoveUpFab(),
                          ),
                        )
                      : null,
                  floatingActionButtonLocation:
                      FloatingActionButtonLocation.endFloat,
                ),
              ),
            ),
        ),
      ),
    );
  }

  Widget _buildLazySection(ProfileSection section) {
    if (!_tabLoadingController.isLoaded(section)) {
      return Builder(
        builder: (context) {
          return CustomScrollView(
            slivers: [
              SliverOverlapInjector(
                handle:
                    NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: PulsatingLoadingIndicator(
                    size: 72.0,
                    assetPath: 'assets/icons/fathemed.png',
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    switch (section) {
      case ProfileSection.home:
        return _buildHomeSection();
      case ProfileSection.gallery:
        return _buildGallerySection();
      case ProfileSection.scraps:
        return _buildScrapsSection();
      case ProfileSection.favs:
        return _buildFavoritesSection();
      case ProfileSection.journals:
        return _buildJournalsSection();
    }
  }

  Future<void> _showEditProfileDialog() async {
    _suppressNextRouteDetach = true;
    final selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      builder: (BuildContext context) {
        return buildEditProfileDialog(
          context: context,
        );
      },
    ).whenComplete(() {
      _suppressNextRouteDetach = false;
    });
    if (!mounted || selected == null) return;
    var changedByScreen = false;
    void markChanged() {
      changedByScreen = true;
    }
    final (screen, analyticsScreen) = switch (selected) {
      'profile_info' => (
          ProfileInfoScreen(onChanged: markChanged),
          AppScreens.furAffinityProfileInfo,
        ),
      'profile_banner' => (
          ProfileBannerScreen(onChanged: markChanged),
          AppScreens.furAffinityProfileBanner,
        ),
      'avatar' => (
          AvatarManagementScreen(onChanged: markChanged),
          AppScreens.furAffinityAvatarManagement,
        ),
      _ => (
          ContactsAndMediaScreen(onChanged: markChanged),
          AppScreens.furAffinityContactsAndMedia,
        ),
    };
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: AnalyticsRouteSettings(analyticsScreen),
        builder: (_) => screen,
      ),
    );
    if (!mounted || (changed != true && !changedByScreen)) return;
    await _fetchUserProfile(afterEdit: true);
    widget.onProfileChanged?.call();
  }

  Widget _buildHomeSection() {
    final webViewKey = _webViewKey;
    return UserProfileHomeSection(
      hasRealUserProfile: _profileController.hasRealUserProfile,
      userDescription: _profileController.userDescription,
      webViewKey: webViewKey,
      descriptionMediaVisibilityKey: _descriptionMediaVisibilityKey,
      sanitizedUsername: _profileController.sanitizedUsername,
      onDescriptionLongPressStart: _handleDescriptionLongPress,
      enableScrollPerformancePause:
          _webViewScrollOptimizationEnabled && _enableScrollWebViewPause,
      gifPlaybackEnabled: _isHomeTabMediaVisible,
      onWebViewLoaded: (loaded) {
        Future<void>.delayed(const Duration(milliseconds: 25), () {
          if (!mounted ||
              !identical(_webViewKey, webViewKey) ||
              _webViewLoaded.value == loaded) {
            return;
          }
          _webViewLoaded.value = loaded;
          final state = webViewKey.currentState;
          if (state == null) {
            return;
          }
          if (_isHomeTabMediaVisible) {
            unawaited(
              state.resumeGifPlayback(
                reason: UserDescriptionWebViewPauseReason.tab,
              ),
            );
          } else {
            unawaited(
              state.pauseGifPlayback(
                reason: UserDescriptionWebViewPauseReason.tab,
              ),
            );
          }
          final descriptionIsActive =
              _descriptionMediaVisibilityKey.currentState?.isActive ?? true;
          if (descriptionIsActive) {
            unawaited(
              state.resumeGifPlayback(
                reason: UserDescriptionWebViewPauseReason.visibility,
              ),
            );
          } else {
            unawaited(
              state.pauseGifPlayback(
                reason: UserDescriptionWebViewPauseReason.visibility,
              ),
            );
          }
        });
      },
      featuredImageUrl: _profileController.featuredImageUrl,
      featuredImageTitle: _profileController.featuredImageTitle,
      featuredPostNumber: _profileController.featuredPostNumber,
      onOpenSubmission: (context, imageUrl, submissionId) {
        Navigator.push(
          context,
          SubmissionDetailsScreen.route(
            imageUrl: imageUrl,
            submissionId: submissionId,
          ),
        );
      },
      userProfileImageUrl: _profileController.userProfileImageUrl,
      userProfilePostNumber: _profileController.userProfilePostNumber,
      userProfileTexts: _profileController.userProfileTexts,
      isClassicMarkup: _profileController.isClassicMarkup,
      acceptingTrades: _profileController.acceptingTrades,
      acceptingCommissions: _profileController.acceptingCommissions,
      onHandleFALink: _handleFALink,
      contactInformationLinks: _profileController.contactInformationLinks,
      onLaunchUrl: _launchURL,
      recentWatchers: _profileController.recentWatchers,
      recentWatchersCount: _profileController.recentWatchersCount,
      recentlyWatched: _profileController.recentlyWatched,
      recentlyWatchedCount: _profileController.recentlyWatchedCount,
      shouts: _profileController.shouts,
      isOwnProfile: _profileController.isOwnProfile,
      selectionController: _shoutSelectionController,
      shoutsRevision: _shoutsRevision,
      currentShoutPage: () => _profileController.currentShoutPage,
      totalShoutPages: () => _profileController.totalShoutPages,
      isLoadingMoreShouts: _isLoadingMoreShouts,
      onOpenPostShout: (context) async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            settings: const AnalyticsRouteSettings(AppScreens.postShout),
            builder: (context) => PostShoutScreen(
              username: _profileController.sanitizedUsername,
            ),
          ),
        );
        if (result == true) {
          await _fetchUserProfile();
        }
      },
      onLoadMoreShouts: _loadMoreShouts,
      onConfirmDeleteShout: _confirmDeleteShout,
      onToggleShoutSelectionMode: _toggleShoutSelectionMode,
      onToggleShoutSelection: _toggleShoutSelection,
    );
  }

  /// Builds the Gallery section content.
  Widget _buildGallerySection() {
    return UserProfileGallerySection(
      nickname: widget.nickname,
      sanitizedUsername: _profileController.sanitizedUsername,
      initialFolderName: widget.initialFolderName,
      initialFolderUrl: widget.initialFolderUrl,
      isOwnProfile: _profileController.isOwnProfile,
      detailFetchesActive: _galleryDetailFetchesActive,
    );
  }

  /// Builds the Scraps section content.
  Widget _buildScrapsSection() {
    return UserProfileScrapsSection(
      sanitizedUsername: _profileController.sanitizedUsername,
      isOwnProfile: _profileController.isOwnProfile,
      onSelectionLayoutChanged: (active, barHeight) {
        _onBulkSelectionLayoutChanged(
          ProfileSection.scraps,
          active,
          barHeight,
        );
      },
    );
  }

  Widget _buildFavoritesSection() {
    return UserProfileFavoritesSection(
      sanitizedUsername: _profileController.sanitizedUsername,
      isOwnProfile: _profileController.isOwnProfile,
      onSelectionLayoutChanged: (active, barHeight) {
        _onBulkSelectionLayoutChanged(
          ProfileSection.favs,
          active,
          barHeight,
        );
      },
    );
  }

  void _refreshJournalsList() {
    final journalsState = _journalsKey.currentState;
    if (journalsState == null) return;
    unawaited(journalsState.refreshJournals());
  }

  /// Builds the Journals section content.
  Widget _buildJournalsSection() {
    return UserProfileJournalsSection(
      sanitizedUsername: _profileController.sanitizedUsername,
      isOwnProfile: _profileController.isOwnProfile,
      journalsKey: _journalsKey,
      onCreateJournalPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            settings:
                const AnalyticsRouteSettings(AppScreens.createJournal),
            builder: (context) => CreateJournalScreen(
              onJournalSubmitted: _refreshJournalsList,
            ),
          ),
        );
      },
    );
  }
}
