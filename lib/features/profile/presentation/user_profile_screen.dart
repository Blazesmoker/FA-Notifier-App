// user_profile_screen.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' as ui;
import 'package:FANotifier/features/profile/presentation/user_description_webview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:FANotifier/main.dart';
import 'package:FANotifier/features/profile/domain/fa_folder.dart';
import 'package:FANotifier/features/profile/domain/profile_section.dart';
import 'package:FANotifier/features/profile/domain/shout.dart';
import 'package:FANotifier/features/profile/domain/user_profile_api_models.dart';
import 'package:FANotifier/features/profile/domain/user_link.dart';
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/shared/fa/fa_username.dart';
import 'package:FANotifier/shared/utils/external_link_launcher.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_styles.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_components.dart';
import 'package:FANotifier/features/journals/presentation/create_journal.dart';
import 'package:FANotifier/features/notes/presentation/new_message.dart';
import 'package:FANotifier/features/journals/presentation/openjournal.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';
import 'package:FANotifier/features/profile/presentation/post_shout.dart';
import 'package:FANotifier/features/profile/presentation/profilejournals.dart';
import 'package:FANotifier/shared/utils/fa_link_matcher.dart';
import 'package:FANotifier/shared/utils/utils.dart';
import 'package:FANotifier/shared/navigation/detachable_webview_route_registry.dart';
import 'package:FANotifier/features/profile/data/user_profile_api_service.dart';
import 'package:FANotifier/features/profile/data/user_profile_action_parser.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_sliver_helpers.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_favorites_section.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_gallery_section.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_home_section.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_journals_section.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_scraps_section.dart';
import 'package:FANotifier/features/settings/data/translator_settings_provider.dart';
import 'package:FANotifier/shared/translation/ios_scroll_recovery.dart';
import 'package:FANotifier/shared/translation/native_translate_launcher.dart';
import 'package:FANotifier/shared/translation/translation_service.dart';
import 'package:provider/provider.dart';

class _TransparentUserProfilePageRoute<T> extends PageRoute<T> {
  _TransparentUserProfilePageRoute({
    required this.builder,
    super.settings,
    super.requestFocus,
    this.allowSnapshotting = true,
    this.fullscreenDialog = false,
    this.maintainState = true,
    this.routeTransitionDuration = const Duration(milliseconds: 280),
    this.routeReverseTransitionDuration = const Duration(milliseconds: 280),
  });

  final WidgetBuilder builder;
  final bool allowSnapshotting;
  @override
  final bool fullscreenDialog;
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

class _ProfileTabKeepAlive extends StatefulWidget {
  const _ProfileTabKeepAlive({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<_ProfileTabKeepAlive> createState() => _ProfileTabKeepAliveState();
}

class _ProfileTabKeepAliveState extends State<_ProfileTabKeepAlive>
    with AutomaticKeepAliveClientMixin<_ProfileTabKeepAlive> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class UserProfileScreen extends StatefulWidget {
  final String nickname;
  final ProfileSection initialSection;
  final String? initialFolderUrl;
  final String? initialFolderName;
  const UserProfileScreen({
    Key? key,
    required this.nickname,
    this.initialSection = ProfileSection.Home,
    this.initialFolderUrl,
    this.initialFolderName,
  }) : super(key: key);

  static Route<T> route<T>({
    required String nickname,
    ProfileSection initialSection = ProfileSection.Home,
    String? initialFolderUrl,
    String? initialFolderName,
    RouteSettings? settings,
    bool instant = false,
  }) {
    final builder = (BuildContext context) => UserProfileScreen(
          nickname: nickname,
          initialSection: initialSection,
          initialFolderUrl: initialFolderUrl,
          initialFolderName: initialFolderName,
        );

    return _TransparentUserProfilePageRoute<T>(
      settings: settings,
      builder: builder,
      routeTransitionDuration:
          instant ? Duration.zero : const Duration(milliseconds: 280),
      routeReverseTransitionDuration:
          instant ? Duration.zero : const Duration(milliseconds: 280),
    );
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
    _tabSettleTimer?.cancel();
    _scrollWebViewResumeTimer?.cancel();
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
  final GlobalKey<UserDescriptionWebViewState> _webViewKey =
      GlobalKey<UserDescriptionWebViewState>();

  late final UserProfileApiService _api;
  final SfwModePreference _sfwModePreference = SfwModePreference();
  final TranslationService _translationService = TranslationService.instance;

  bool _sfwEnabled = true;

  Future<void> _loadSfwEnabled() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    setState(() {
      _sfwEnabled = sfwEnabled;
    });
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
    if (selected == 'copy') {
      final plainText = await _webViewKey.currentState?.getPlainText();
      if (plainText != null) {
        await Clipboard.setData(ClipboardData(text: plainText));
        showAppSnackBar(context, 'Text copied to clipboard',
            backgroundColor: Colors.green);
      }
    } else if (selected == 'select') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserDescriptionWebViewScreen(
            sanitizedUsername: sanitizedUsername,
            initialHtml: userDescription,
          ),
        ),
      );
    }
  }

  String _selectedFolderName = 'Main Gallery';
  String _selectedFolderUrl = '';
  List<FaFolder> _allFolders = [];

  UserProfileParsed? _profileParsed;

  String? get profileBannerUrl => _profileParsed?.profileBannerUrl;
  String? get profileImageUrl => _profileParsed?.profileImageUrl;
  String? get profileDisplayName => _profileParsed?.profileDisplayName;
  String? get profileUserNamePart => _profileParsed?.profileUserNamePart;
  String? get symbolUsername => _profileParsed?.symbolUsername;
  String? get username => _profileParsed?.username;
  String? get userTitle => _profileParsed?.userTitle;
  String? get registrationDate => _profileParsed?.registrationDate;
  String? get userDescription => _profileParsed?.userDescription;
  bool get hasRealUserProfile => _profileParsed?.hasRealUserProfile ?? true;

  String _profileTranslationSourceText() {
    return _translationService.plainTextFromHtml(userDescription ?? '');
  }

  Future<void> _openProfileTranslation(
    TranslatorSettingsProvider settings,
  ) async {
    final webViewText = await _webViewKey.currentState?.getPlainText();
    await NativeTranslateLauncher.open(
      webViewText?.trim().isNotEmpty == true
          ? webViewText!
          : _profileTranslationSourceText(),
      targetLanguageCode: settings.targetLanguageCode,
    );
  }

  bool get isClassicMarkup => _profileParsed?.isClassicMarkup ?? false;
  bool get acceptingTrades => _profileParsed?.acceptingTrades ?? false;
  bool get acceptingCommissions =>
      _profileParsed?.acceptingCommissions ?? false;

  List<String> get userIconBeforeUrls =>
      _profileParsed?.userIconBeforeUrls ?? const [];
  List<String> get userIconAfterUrls =>
      _profileParsed?.userIconAfterUrls ?? const [];

  int? get views => _profileParsed?.views;
  int? get submissions => _profileParsed?.submissions;
  int? get favs => _profileParsed?.favs;
  int? get commentsEarned => _profileParsed?.commentsEarned;
  int? get commentsMade => _profileParsed?.commentsMade;
  int? get journals => _profileParsed?.journals;

  bool get isWatching => _profileParsed?.isWatching ?? false;
  String? get watchLink => _profileParsed?.watchLink;
  String? get unwatchLink => _profileParsed?.unwatchLink;
  String? get unblockLink => _profileParsed?.unblockLink;
  String? get blockLink => _profileParsed?.blockLink;
  bool get isBlocked => _profileParsed?.isBlocked ?? false;
  bool get blockUsesPost => _profileParsed?.blockUsesPost ?? false;
  bool get unblockUsesPost => _profileParsed?.unblockUsesPost ?? false;

  String? get featuredImageUrl => _profileParsed?.featuredImageUrl;
  String? get featuredImageTitle => _profileParsed?.featuredImageTitle;
  String? get featuredPostNumber => _profileParsed?.featuredPostNumber;

  String? get userProfileImageUrl => _profileParsed?.userProfileImageUrl;
  String? get userProfilePostNumber => _profileParsed?.userProfilePostNumber;
  String? get userProfileTexts => _profileParsed?.userProfileTexts;

  List<Map<String, String>> get contactInformationLinks =>
      _profileParsed?.contactInformationLinks ?? const [];

  List<UserLink> get recentWatchers =>
      _profileParsed?.recentWatchers ?? const [];
  int get recentWatchersCount => _profileParsed?.recentWatchersCount ?? 0;

  List<UserLink> get recentlyWatched =>
      _profileParsed?.recentlyWatched ?? const [];
  int get recentlyWatchedCount => _profileParsed?.recentlyWatchedCount ?? 0;

  List<Shout> get shouts => _profileParsed?.shouts ?? <Shout>[];
  String? get shoutPaginationKey => _profileParsed?.shoutPaginationKey;
  int get currentShoutPage => _profileParsed?.currentShoutPage ?? 1;
  int get totalShoutPages => _profileParsed?.totalShoutPages ?? 1;

  bool get isOwnProfile => _profileParsed?.isOwnProfile ?? false;

  void _onFoldersParsed(List<FaFolder> folders) {
    setState(() {
      if (_selectedFolderUrl.isNotEmpty) {
        final matchingFolder = folders.firstWhere(
          (folder) => areFaFolderUrlsEquivalent(folder.url, _selectedFolderUrl),
          orElse: () =>
              FaFolder(name: _selectedFolderName, url: _selectedFolderUrl),
        );
        _selectedFolderName = matchingFolder.name;
        if (!areFaFolderUrlsEquivalent(
            matchingFolder.url, _selectedFolderUrl)) {
          _selectedFolderUrl = matchingFolder.url;
        }
      } else if (folders.isNotEmpty) {
        final mainGallery = folders.firstWhere(
          (f) => f.name == 'Main Gallery',
          orElse: () => folders.first,
        );
        _selectedFolderName = mainGallery.name;
      }

      _allFolders = folders;
    });
  }

  void _onFolderSelected(FaFolder folder) {
    setState(() {
      _selectedFolderName = folder.name;
      _selectedFolderUrl = folder.url;
    });
  }

  String sanitizedUsername = '';
  bool isLoading = true;
  bool _webViewLoaded = false;
  String errorMessage = '';

  static const double sliverAppBarExpandedHeight = 120.0;
  static const double sliverAppBarMinHeight = kToolbarHeight - 80.0; // 56.0
  static const double collapsibleHeaderMaxHeight = 110.0;
  static const double navigationSliderHeight = 64.0;
  static const double _profileAvatarLeft = 16.0;
  static const double _profileAvatarSize = 90.0;
  static const double _profileAvatarBorderWidth = 2.0;

  static const double _profileAvatarMinScale = 0.53;
  static const double _profileAvatarScrollDownDistance = 16.0;
  static const double _profileAvatarScrollDownEnd = 64.0;
  static const double _profileAvatarBehindBannerStart = 63.0;

  static const double _edgeBackSwipeDetectorWidth = 25.0;
  static const double _edgeBackSwipeTriggerWidth = 62.0;
  static const double _edgeBackSwipeMinDistance = 72.0;
  static const double _edgeBackSwipeMinVelocity = 700.0;
  static const bool _webViewScrollOptimizationEnabled = false;

  late ScrollController _scrollController;
  late final ValueNotifier<bool> _showMoveUpFab = ValueNotifier<bool>(false);
  late final ValueNotifier<double> _backSwipeOffsetNotifier =
      ValueNotifier<double>(0.0);
  late final AnimationController _backSwipeAnimationController;
  Animation<double>? _backSwipeOffsetAnimation;
  bool _popAfterBackSwipeAnimation = false;

  late TabController _tabController;

  static const Duration _tabSettleDelay = Duration(milliseconds: 100);
  static const Duration _scrollWebViewResumeDelay = Duration(milliseconds: 50);
  Timer? _tabSettleTimer;
  Timer? _scrollWebViewResumeTimer;
  final Set<ProfileSection> _lazyLoadedSections = <ProfileSection>{};

  int _previousIndex = 0;

  bool isLoadingMoreShouts = false;
  bool _isShoutSelectionMode = false;
  bool _isDeletingSelectedShouts = false;
  bool _isDraggingBackFromEdge = false;
  bool _isProfileWebViewDetached = false;
  bool _suppressNextRouteDetach = false;
  bool _didTemporarilyRestorePreviousForSwipe = false;
  bool _isWebViewPausedForScroll = false;
  bool _enableScrollWebViewPause = false;
  int _frameTimingCount = 0;
  int _frameTimingTotalMicros = 0;
  int _iosScrollRecoveryKey = IosScrollRecovery.revision;
  bool _shouldShowProfileAvatarBorder = false;
  String? _profileAvatarTransparencyCheckedUrl;
  int _profileAvatarTransparencyCheckGeneration = 0;
  double _backDragStartX = 0.0;
  double _backDragDistance = 0.0;

  double get _backSwipeOffset => _backSwipeOffsetNotifier.value;
  set _backSwipeOffset(double value) => _backSwipeOffsetNotifier.value = value;

  @override
  void initState() {
    super.initState();
    DetachableWebViewRouteRegistry.register(this);

    _api = UserProfileApiService();
    if (_webViewScrollOptimizationEnabled) {
      SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
    }
    IosScrollRecovery.addListener(_handleIosScrollRecovery);

    if (widget.initialFolderUrl != null &&
        widget.initialFolderUrl!.isNotEmpty) {
      _selectedFolderUrl = widget.initialFolderUrl!;
      _selectedFolderName = widget.initialFolderName ?? _selectedFolderName;
    }
    if (widget.initialSection != ProfileSection.Home) {
      _webViewLoaded = true;
    }

    _loadSfwEnabled();

    _scrollController = ScrollController();
    _scrollController.addListener(_onProfileScroll);

    _tabController = TabController(
      length: ProfileSection.values.length,
      vsync: this,
      initialIndex: widget.initialSection.index,
    );
    _backSwipeAnimationController = AnimationController(vsync: this)
      ..addListener(_onBackSwipeAnimationTick)
      ..addStatusListener(_onBackSwipeAnimationStatusChanged);

    // Load only the initial tab immediately; others will load after "settling".
    _lazyLoadedSections.add(ProfileSection.values[_tabController.index]);

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        // Cancel any pending lazy-load while the tab is still animating/dragging.
        _tabSettleTimer?.cancel();
        return;
      }

      // Tab finished changing; schedule lazy-load for the final tab.
      _scheduleLazyLoadForIndex(_tabController.index);

      if (_previousIndex != _tabController.index) {
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

    sanitizedUsername = _sanitizeUsername(widget.nickname);

    _initAsyncFetch();
  }

  @override
  void didPushNext() {
    if (_suppressNextRouteDetach) {
      return;
    }
    _setRouteWebViewDetached(true);
  }

  @override
  void didPopNext() {
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

  void _scheduleLazyLoadForIndex(int index) {
    _tabSettleTimer?.cancel();
    _tabSettleTimer = Timer(_tabSettleDelay, () {
      if (!mounted) return;
      if (_tabController.index != index) return;
      final section = ProfileSection.values[index];
      if (_lazyLoadedSections.contains(section)) return;
      setState(() {
        _lazyLoadedSections.add(section);
      });
    });
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

  Future<void> _initAsyncFetch() async {
    await _loadSfwEnabled();
    await _fetchUserProfile();
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
      case ProfileSection.Home:
        return Icons.home;
      case ProfileSection.Gallery:
        return Icons.photo;
      case ProfileSection.Scraps:
        return Icons.collections_bookmark;
      case ProfileSection.Favs:
        return Icons.favorite;
      case ProfileSection.Journals:
        return Icons.book;
    }
  }

  String _getTabTitle(ProfileSection section) {
    switch (section) {
      case ProfileSection.Home:
        return 'Home';
      case ProfileSection.Gallery:
        return 'Gallery';
      case ProfileSection.Scraps:
        return 'Scraps';
      case ProfileSection.Favs:
        return 'Favs';
      case ProfileSection.Journals:
        return 'Journals';
    }
  }

  Future<void> _sendWatchUnwatchRequest(String urlPath,
      {required bool shouldWatch}) async {
    final result = await _api.sendWatchUnwatchRequest(
      urlPath,
      shouldWatch: shouldWatch,
      sfwEnabled: _sfwEnabled,
    );

    if (result.missingCookies) {
      debugPrint('No cookies found. User might not be logged in.');
      showAppSnackBar(context, 'Please log in to perform this action.',
          backgroundColor: Colors.red);
      return;
    }

    if (result.success) {
      debugPrint('${shouldWatch ? 'Watch' : 'Unwatch'} action successful.');

      setState(() {
        _profileParsed?.isWatching = shouldWatch;
      });

      showAppSnackBar(
        context,
        '${shouldWatch ? 'Now watching $username' : 'Stopped watching $username'}',
        backgroundColor: Colors.green,
      );
    } else if (result.error != null) {
      debugPrint(
          'Error during ${shouldWatch ? 'watch' : 'unwatch'}: ${result.error}');
      showAppSnackBar(
        context,
        'An error occurred while trying to ${shouldWatch ? 'watch' : 'unwatch'} user.',
        backgroundColor: Colors.red,
      );
    } else {
      debugPrint(
          'Failed to ${shouldWatch ? 'watch' : 'unwatch'}. Status code: ${result.statusCode}');
      showAppSnackBar(
        context,
        'Failed to ${shouldWatch ? 'watch' : 'unwatch'} user.',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _handleWatchButtonPressed() async {
    if (isWatching) {
      if (unwatchLink == null) {
        debugPrint('Unwatch link not available.');
        return;
      }
      await _sendWatchUnwatchRequest(unwatchLink!, shouldWatch: false);
      _fetchUserProfile();
    } else {
      if (watchLink == null) {
        debugPrint('Watch link not available.');
        return;
      }
      await _sendWatchUnwatchRequest(watchLink!, shouldWatch: true);
      _fetchUserProfile();
    }
  }

  int get _selectedShoutCount => shouts.where((shout) => shout.selected).length;

  void _toggleShoutSelectionMode() {
    setState(() {
      final nextValue = !_isShoutSelectionMode;
      _isShoutSelectionMode = nextValue;
      if (!nextValue) {
        for (final shout in shouts) {
          shout.selected = false;
        }
      }
    });
  }

  void exitShoutSelectionMode() {
    if (!_isShoutSelectionMode) {
      return;
    }
    setState(() {
      _isShoutSelectionMode = false;
      for (final shout in shouts) {
        shout.selected = false;
      }
    });
  }

  void _toggleShoutSelection(Shout shout) {
    if (!_isShoutSelectionMode) {
      return;
    }

    setState(() {
      shout.selected = !shout.selected;
    });
  }

  Future<bool> _showDeleteShoutsDialog(List<Shout> shoutsToDelete) async {
    final bool isSingle = shoutsToDelete.length == 1;
    final String title =
        isSingle ? 'Confirm deletion' : 'Delete selected shouts';
    final String message = isSingle
        ? 'Are you sure you want to delete shout from ${shoutsToDelete.first.username}?'
        : 'Are you sure you want to delete ${shoutsToDelete.length} selected shouts?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.55;
        final dialogHeight = isSingle ? min(maxHeight, 320.0) : maxHeight;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            height: dialogHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: shoutsToDelete.length > 2,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: shoutsToDelete.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final shout = shoutsToDelete[index];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F1F1F),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: FaNetworkImage(
                                      shout.avatarUrl,
                                      width: 42,
                                      height: 42,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Image.asset(
                                          'assets/images/defaultpic.gif',
                                          width: 42,
                                          height: 42,
                                          fit: BoxFit.cover,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          shout.username,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if ((shout.symbol?.isNotEmpty ??
                                                false) ||
                                            shout.profileNickname.isNotEmpty)
                                          Text(
                                            '${shout.symbol ?? '~'} ${shout.profileNickname}'
                                                .trim(),
                                            style: const TextStyle(
                                              color: Color(0xFFE09321),
                                              fontSize: 13,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              html_pkg.Html(
                                data: shout.text,
                                style: userProfileHtmlStyles(),
                                extensions: buildUserProfileBBCodeExtensions(),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(isSingle ? 'Delete' : 'Delete Selected'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _confirmDeleteSelectedShouts() async {
    if (!isOwnProfile || _isDeletingSelectedShouts) {
      return;
    }

    final selectedShouts =
        shouts.where((shout) => shout.selected).toList(growable: false);
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
    if (!isOwnProfile) {
      return;
    }

    final confirmed = await _showDeleteShoutsDialog([shout]);
    if (confirmed) {
      await _deleteShout(index, shout);
    }
  }

  Future<void> _deleteShout(int _, Shout shout) async {
    await _deleteShouts([shout]);
  }

  Future<void> _deleteShouts(List<Shout> shoutsToDelete) async {
    if (shoutsToDelete.isEmpty || _isDeletingSelectedShouts) {
      return;
    }

    final loadedProfilePage = currentShoutPage;

    setState(() {
      _isDeletingSelectedShouts = true;
    });

    try {
      final resolvedShouts = await _api.resolveControlsShouts(
        shouts: shoutsToDelete,
        sfwEnabled: _sfwEnabled,
      );

      if (resolvedShouts.length != shoutsToDelete.length) {
        showAppSnackBar(
          context,
          "Failed to match one or more selected shouts on the controls page.",
          backgroundColor: Colors.red,
        );
        return;
      }

      final shoutIdsByPage = <int, List<String>>{};
      for (final resolvedShout in resolvedShouts) {
        shoutIdsByPage.putIfAbsent(resolvedShout.page, () => <String>[]);
        shoutIdsByPage[resolvedShout.page]!.add(resolvedShout.id);
      }

      final pages = shoutIdsByPage.keys.toList()
        ..sort((a, b) => b.compareTo(a));
      bool anySuccess = false;
      DeleteShoutResult? failedResult;

      for (final page in pages) {
        final result = await _api.deleteShouts(
          shoutIds: shoutIdsByPage[page]!,
          sfwEnabled: _sfwEnabled,
          page: page,
        );

        if (result.success) {
          anySuccess = true;
          continue;
        }

        failedResult = result;
        break;
      }

      if (failedResult?.missingCookies == true) {
        showAppSnackBar(context, "Please log in to perform this action.",
            backgroundColor: Colors.red);
      } else if (failedResult == null) {
        final deletedCount = shoutsToDelete.length;
        showAppSnackBar(
          context,
          deletedCount == 1
              ? "Shout deleted."
              : "$deletedCount shouts deleted.",
          backgroundColor: Colors.green,
        );
        setState(() {
          _isShoutSelectionMode = false;
          for (final shout in shouts) {
            shout.selected = false;
          }
        });
        await _fetchUserProfile();
        await _restoreLoadedShoutPages(loadedProfilePage);
      } else if (anySuccess) {
        showAppSnackBar(
          context,
          "Some selected shouts were deleted, but one page failed.",
          backgroundColor: Colors.red,
        );
        setState(() {
          _isShoutSelectionMode = false;
          for (final shout in shouts) {
            shout.selected = false;
          }
        });
        await _fetchUserProfile();
        await _restoreLoadedShoutPages(loadedProfilePage);
      } else if (failedResult.error != null) {
        showAppSnackBar(context, "Error: ${failedResult.error}",
            backgroundColor: Colors.red);
      } else {
        showAppSnackBar(context, "Failed to delete shout.",
            backgroundColor: Colors.red);
      }
    } catch (e) {
      showAppSnackBar(context, "Error: $e", backgroundColor: Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingSelectedShouts = false;
        });
      }
    }
  }

  Future<void> _restoreLoadedShoutPages(int targetPage) async {
    while (mounted &&
        currentShoutPage < targetPage &&
        currentShoutPage < totalShoutPages) {
      await _loadMoreShouts();
    }
  }

  Future<void> _launchURL(String url) async {
    if (!await tryLaunchExternalUrl(url)) {
      debugPrint('Could not launch $url');
      showAppSnackBar(context, 'Could not launch URL: $url',
          backgroundColor: Colors.red);
    }
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
        exitShoutSelectionMode();
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
        await launchUrlString(url, mode: LaunchMode.externalApplication);
        return;
    }
  }

  /// Fetches the user's profile data from FurAffinity.
  Future<void> _fetchUserProfile() async {
    try {
      final payload = await _api.fetchProfile(
        nickname: widget.nickname,
        sfwEnabled: _sfwEnabled,
      );

      sanitizedUsername = payload.sanitizedUsername;

      final parsed = await compute(parseUserProfileHtml, payload.htmlBody);
      final bool shouldShowDescription = parsed.hasRealUserProfile &&
          parsed.userDescription != null &&
          parsed.userDescription!.trim().isNotEmpty;

      setState(() {
        _profileParsed = parsed;
        _webViewLoaded = shouldShowDescription ? _webViewLoaded : true;
        isLoading = false;
      });
      _updateProfileAvatarTransparency(parsed.profileImageUrl);

      debugPrint("Block/Unblock Link: $blockLink / $unblockLink");
      debugPrint("Watch/Unwatch Link: $watchLink / $unwatchLink");
      debugPrint("isBlocked: $isBlocked");
    } on StateError catch (e) {
      setState(() {
        errorMessage = e.message;
        isLoading = false;
      });
      debugPrint(e.toString());
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
        isLoading = false;
      });
      debugPrint("An error occurred while fetching profile: $e");
    }
  }

  String _sanitizeUsername(String username) {
    return sanitizeFAUsername(username);
  }

  void switchToGalleryTab() {
    _tabController.animateTo(ProfileSection.Gallery.index);
  }

  Future<void> _loadMoreShouts() async {
    if (isLoadingMoreShouts || currentShoutPage >= totalShoutPages) {
      debugPrint(
          "Cannot load more shouts. Loading: $isLoadingMoreShouts, Current: $currentShoutPage, Total: $totalShoutPages");
      return;
    }

    setState(() {
      isLoadingMoreShouts = true;
    });

    try {
      final nextPage = currentShoutPage + 1;
      final payload = await _api.fetchAdditionalShouts(
        sanitizedUsername: sanitizedUsername,
        shoutPaginationKey: shoutPaginationKey,
        nextPage: nextPage,
        sfwEnabled: _sfwEnabled,
        existingShoutIds: shouts.map((s) => s.id).toSet(),
      );

      if (payload == null) {
        debugPrint("Missing shout pagination key; cannot load more shouts.");
        return;
      }

      setState(() {
        _profileParsed?.shouts.addAll(payload.newShouts);
        if (_profileParsed != null) {
          _profileParsed!.currentShoutPage = payload.nextPage;
        }
      });
    } catch (e) {
      debugPrint('Error loading more shouts: $e');
      showAppSnackBar(context, 'Failed to load more shouts',
          backgroundColor: Colors.red);
    } finally {
      setState(() {
        isLoadingMoreShouts = false;
      });
    }
  }

  // Animated banner/avatar helpers
  Widget buildAnimatedBanner(BoxConstraints constraints) {
    double alignmentX = -1.0;
    if (profileBannerUrl?.contains('fa-banner') ?? false) {
      double shiftFraction = 30.0 / constraints.maxWidth * 2;
      alignmentX += shiftFraction;
    }

    return RepaintBoundary(
      child: FaNetworkImage(
        profileBannerUrl ??
            'https://d.furaffinity.net/media/banners/modern/fa-banner-summer.jpg',
        fit: BoxFit.cover,
        alignment: Alignment(alignmentX, 0),
        gaplessPlayback: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(color: Colors.grey);
        },
      ),
    );
  }

  Widget buildAnimatedAvatar(double offset, Widget avatarChild) {
    final double scaleProgress =
        (offset / _profileAvatarScrollDownEnd).clamp(0.0, 1.0).toDouble();
    final double scale = 1.0 - ((1.0 - _profileAvatarMinScale) * scaleProgress);
    final double scrollPastShrink =
        max(0.0, offset - _profileAvatarScrollDownEnd);
    final double translateY =
        (_profileAvatarScrollDownDistance * scaleProgress) - scrollPastShrink;

    return Positioned(
      key: const ValueKey<String>('profileAvatar'),
      bottom: -_profileAvatarSize / 1.5 - _profileAvatarBorderWidth,
      left: _profileAvatarLeft - _profileAvatarBorderWidth,
      child: Transform.translate(
        offset: Offset(0.0, translateY),
        child: Transform.scale(
          scale: scale,
          child: avatarChild,
        ),
      ),
    );
  }

  void _updateProfileAvatarTransparency(String? imageUrl) {
    final String? trimmedUrl = imageUrl?.trim();
    final int generation = ++_profileAvatarTransparencyCheckGeneration;
    if (trimmedUrl == null || trimmedUrl.isEmpty) {
      _profileAvatarTransparencyCheckedUrl = null;
      if (!_shouldShowProfileAvatarBorder && mounted) {
        setState(() {
          _shouldShowProfileAvatarBorder = true;
        });
      }
      return;
    }
    if (_profileAvatarTransparencyCheckedUrl == trimmedUrl) {
      return;
    }
    _profileAvatarTransparencyCheckedUrl = trimmedUrl;
    if (_shouldShowProfileAvatarBorder && mounted) {
      setState(() {
        _shouldShowProfileAvatarBorder = false;
      });
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
              await _imageHasTransparentEdge(imageInfo.image);
          if (!mounted ||
              generation != _profileAvatarTransparencyCheckGeneration ||
              _profileAvatarTransparencyCheckedUrl != trimmedUrl) {
            return;
          }
          final bool shouldShowBorder = !hasTransparentEdge;
          if (_shouldShowProfileAvatarBorder != shouldShowBorder) {
            setState(() {
              _shouldShowProfileAvatarBorder = shouldShowBorder;
            });
          }
        },
        onError: (Object error, StackTrace? stackTrace) {
          stream.removeListener(listener);
          if (!mounted ||
              generation != _profileAvatarTransparencyCheckGeneration ||
              _profileAvatarTransparencyCheckedUrl != trimmedUrl) {
            return;
          }
          if (!_shouldShowProfileAvatarBorder) {
            setState(() {
              _shouldShowProfileAvatarBorder = true;
            });
          }
        },
      );
      stream.addListener(listener);
    });
  }

  Future<bool> _imageHasTransparentEdge(ui.Image image) async {
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null || image.width <= 0 || image.height <= 0) {
      return false;
    }

    bool isTransparentAt(int x, int y) {
      final int alphaIndex = ((y * image.width + x) * 4) + 3;
      return bytes.getUint8(alphaIndex) < 255;
    }

    for (int x = 0; x < image.width; x++) {
      if (isTransparentAt(x, 0) || isTransparentAt(x, image.height - 1)) {
        return true;
      }
    }
    for (int y = 0; y < image.height; y++) {
      if (isTransparentAt(0, y) || isTransparentAt(image.width - 1, y)) {
        return true;
      }
    }
    return false;
  }

  Widget buildAvatarImage() {
    final double outerAvatarSize =
        _profileAvatarSize + (_profileAvatarBorderWidth * 2.0);
    final Widget avatarImage =
        profileImageUrl == null || profileImageUrl!.isEmpty
            ? Image.asset(
                'assets/images/defaultpic.gif',
                width: _profileAvatarSize,
                height: _profileAvatarSize,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : FaNetworkImage(
                profileImageUrl!,
                width: _profileAvatarSize,
                height: _profileAvatarSize,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return SizedBox(
                    width: _profileAvatarSize / 2,
                    height: _profileAvatarSize / 2,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Image.asset(
                    'assets/images/defaultpic.gif',
                    width: _profileAvatarSize,
                    height: _profileAvatarSize,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  );
                },
              );

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {},
        child: SizedBox(
          width: outerAvatarSize,
          height: outerAvatarSize,
          child: Stack(
            children: [
              Positioned(
                left: _profileAvatarBorderWidth,
                top: _profileAvatarBorderWidth,
                child: avatarImage,
              ),
              if (_shouldShowProfileAvatarBorder)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFF111111),
                          width: _profileAvatarBorderWidth,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  GlobalKey _profileNameRowKey = GlobalKey();

  void _clearProfileNameSelection() {
    setState(() {
      _profileNameRowKey = GlobalKey();
    });
  }

  void _copyProfileLinkToClipboard() {
    final profileLink = 'https://www.furaffinity.net/user/$sanitizedUsername/';
    Clipboard.setData(ClipboardData(text: profileLink)).then((_) {
      showAppSnackBar(context, 'Copied profile link!',
          backgroundColor: Colors.green);
    }).catchError((error) {
      debugPrint('Failed to copy profile link: $error');
      showAppSnackBar(context, 'Failed to copy profile link.',
          backgroundColor: Colors.red);
    });
  }

  Widget _buildProfileHeaderNameRow() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (TapDownDetails details) {
        final RenderBox? renderBox =
            _profileNameRowKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final Offset localPosition =
              renderBox.globalToLocal(details.globalPosition);
          if (!renderBox.size.contains(localPosition)) {
            _clearProfileNameSelection();
          }
        } else {
          _clearProfileNameSelection();
        }
      },
      child: Container(
        key: _profileNameRowKey,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (userIconBeforeUrls.isNotEmpty)
              ...userIconBeforeUrls.map(
                (url) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FaNetworkImage(url, width: 20, height: 20),
                ),
              ),
            SelectableLinkify(
              text: profileDisplayName ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
              ),
              onOpen: (link) async {},
              selectionControls: MaterialTextSelectionControls(),
            ),
            const SizedBox(width: 4),
            if (userIconAfterUrls.isNotEmpty)
              ...userIconAfterUrls.map(
                (url) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FaNetworkImage(url, width: 20, height: 20),
                ),
              ),
            SelectableLinkify(
              text: profileUserNamePart ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20.0,
              ),
              onOpen: (link) async {},
              selectionControls: MaterialTextSelectionControls(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendBlockUnblockRequest(
    String urlOrPath,
    String keyValue, {
    required bool shouldBlock,
    required bool usePost,
  }) async {
    final result = await _api.sendBlockUnblockRequest(
      urlOrPath,
      keyValue,
      shouldBlock: shouldBlock,
      usePost: usePost,
      sfwEnabled: _sfwEnabled,
      sanitizedUsername: sanitizedUsername,
    );

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
    if (isBlocked) {
      if (unblockLink == null) {
        showAppSnackBar(
          context,
          'Cannot unblock author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }
      final key = extractBlockUnblockKey(unblockLink!);

      if (key == null || key.isEmpty) {
        showAppSnackBar(
          context,
          'Cannot unblock author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }

      await _sendBlockUnblockRequest(
        unblockLink!,
        key,
        shouldBlock: false,
        usePost: unblockUsesPost,
      );
    } else {
      if (blockLink == null) {
        showAppSnackBar(
          context,
          'Cannot block author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }

      final key = extractBlockUnblockKey(blockLink!);

      if (key == null || key.isEmpty) {
        showAppSnackBar(
          context,
          'Cannot block author at this time.',
          backgroundColor: Colors.red,
        );
        return;
      }

      await _sendBlockUnblockRequest(
        blockLink!,
        key,
        shouldBlock: true,
        usePost: blockUsesPost,
      );
    }
  }

  /// Builds the main UI of the screen with unified scrolling.
  @override
  Widget build(BuildContext context) {
    // Define constants for the avatar and text alignment.
    const double avatarLeft = 16.0;
    const double avatarWidth = 90.0;
    const double marginBetweenAvatarAndText = 0.0;
    final double textLeftPadding =
        avatarLeft + avatarWidth + marginBetweenAvatarAndText;
    final bool needsDescriptionLoad =
        hasRealUserProfile && userDescription != null;
    bool showLoadingIndicator = isLoading ||
        (needsDescriptionLoad &&
            !_webViewLoaded &&
            _tabController.index == ProfileSection.Home.index);
    final platformViews = WidgetsBinding.instance.platformDispatcher.views;
    final baseView =
        platformViews.isNotEmpty ? platformViews.first : View.of(context);
    final fixedTextScaleMediaQuery = MediaQueryData.fromView(baseView)
        .copyWith(textScaler: TextScaler.linear(1.0));
    final bool showDeleteSelectedFab = !isLoading &&
        isOwnProfile &&
        _isShoutSelectionMode &&
        _selectedShoutCount > 0;
    final translatorSettings = context.watch<TranslatorSettingsProvider>();

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
          child: DefaultTabController(
            length: ProfileSection.values.length,
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
                                            symbolUsername ?? 'Profile',
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
                                            symbolUsername ?? 'Profile',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18.0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (symbolUsername != null &&
                                          symbolUsername!.startsWith('!'))
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
                                            if (!isOwnProfile) {
                                              await _handleBlockUnblock();
                                            }
                                            break;
                                          case 'copy_link':
                                            _copyProfileLinkToClipboard();
                                            break;
                                          case 'translate':
                                            await _openProfileTranslation(
                                              translatorSettings,
                                            );
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem<String>(
                                          value: 'report',
                                          child: Text('Report'),
                                        ),
                                        if (!isOwnProfile)
                                          PopupMenuItem<String>(
                                            value: 'block_unblock',
                                            child: Text(isBlocked
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
                                    builder: (context, constraints) {
                                      final Widget staticBannerLayers =
                                          Positioned.fill(
                                        key: const ValueKey<String>(
                                            'profileBannerLayer'),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            buildAnimatedBanner(constraints),
                                            ColoredBox(
                                              color: Colors.black
                                                  .withValues(alpha: 0.15),
                                            ),
                                          ],
                                        ),
                                      );

                                      return AnimatedBuilder(
                                        animation: _scrollController,
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
                                SliverPersistentHeader(
                                  delegate: FixedSliverPersistentHeaderDelegate(
                                    height: 160,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const Divider(
                                          height: 4.0,
                                          color: Color(0xFF111111),
                                          thickness: 3.0,
                                        ),
                                        const Divider(
                                          height: 2.0,
                                          color: Colors.black,
                                          thickness: 1.0,
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: double.infinity,
                                              color: const Color(0xFF111111),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        8.0, 0.0, 8.0, 8.0),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    MediaQuery(
                                                      data:
                                                          fixedTextScaleMediaQuery,
                                                      child: Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            SizedBox(
                                                              height: 30.0,
                                                              child: Padding(
                                                                padding: EdgeInsets
                                                                    .only(
                                                                        left:
                                                                            textLeftPadding),
                                                                child:
                                                                    FittedBox(
                                                                  fit: BoxFit
                                                                      .scaleDown,
                                                                  alignment:
                                                                      Alignment
                                                                          .centerLeft,
                                                                  child:
                                                                      _buildProfileHeaderNameRow(),
                                                                ),
                                                              ),
                                                            ),
                                                            SizedBox(
                                                              height: 24.0,
                                                              child: Visibility(
                                                                visible: true,
                                                                maintainSize:
                                                                    true,
                                                                maintainAnimation:
                                                                    true,
                                                                maintainState:
                                                                    true,
                                                                child: Padding(
                                                                  padding:
                                                                      EdgeInsets
                                                                          .only(
                                                                    top: 0.0,
                                                                    left:
                                                                        textLeftPadding,
                                                                  ),
                                                                  child:
                                                                      FittedBox(
                                                                    fit: BoxFit
                                                                        .scaleDown,
                                                                    alignment:
                                                                        Alignment
                                                                            .center,
                                                                    child: Text(
                                                                      (userTitle?.isNotEmpty ??
                                                                              false)
                                                                          ? userTitle!
                                                                          : " ",
                                                                      style:
                                                                          const TextStyle(
                                                                        color: Colors
                                                                            .white70,
                                                                        fontSize:
                                                                            16.0,
                                                                      ),
                                                                      maxLines:
                                                                          1,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                top: 8.0,
                                                                left: 0.0,
                                                              ),
                                                              child: FittedBox(
                                                                fit: BoxFit
                                                                    .scaleDown,
                                                                alignment: Alignment
                                                                    .centerLeft,
                                                                child: Text(
                                                                  registrationDate !=
                                                                              null &&
                                                                          registrationDate!
                                                                              .isNotEmpty
                                                                      ? 'Joined $registrationDate'
                                                                      : '',
                                                                  style:
                                                                      const TextStyle(
                                                                    color: Colors
                                                                        .white70,
                                                                    fontSize:
                                                                        14.0,
                                                                  ),
                                                                  maxLines: 1,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    if (isOwnProfile)
                                                      SizedBox(
                                                        width: 100,
                                                        height: 38,
                                                        child: ElevatedButton(
                                                          onPressed:
                                                              _showEditProfileDialog,
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                Colors.black,
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          2),
                                                            ),
                                                            side:
                                                                const BorderSide(
                                                              color: Color(
                                                                  0xFFE09321),
                                                            ),
                                                          ),
                                                          child:
                                                              const FittedBox(
                                                            fit: BoxFit
                                                                .scaleDown,
                                                            child: Text(
                                                              "Edit Profile",
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    else
                                                      Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          SizedBox(
                                                            width: 100,
                                                            height: 38,
                                                            child:
                                                                ElevatedButton(
                                                              onPressed:
                                                                  _handleWatchButtonPressed,
                                                              style:
                                                                  ElevatedButton
                                                                      .styleFrom(
                                                                backgroundColor:
                                                                    Colors
                                                                        .black,
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              2),
                                                                ),
                                                                side:
                                                                    const BorderSide(
                                                                  color: Color(
                                                                      0xFFE09321),
                                                                ),
                                                              ),
                                                              child: FittedBox(
                                                                fit: BoxFit
                                                                    .scaleDown,
                                                                child: Text(
                                                                  isWatching
                                                                      ? "-Watch"
                                                                      : "+Watch",
                                                                  style:
                                                                      const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 5),
                                                          SizedBox(
                                                            width: 100,
                                                            height: 38,
                                                            child:
                                                                ElevatedButton(
                                                              onPressed: () {
                                                                Navigator.push(
                                                                  context,
                                                                  MaterialPageRoute(
                                                                    builder:
                                                                        (context) =>
                                                                            NewMessageScreen(
                                                                      recipient:
                                                                          sanitizedUsername,
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                              style:
                                                                  ElevatedButton
                                                                      .styleFrom(
                                                                backgroundColor:
                                                                    const Color(
                                                                        0xFFE09321),
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              2),
                                                                ),
                                                              ),
                                                              child:
                                                                  const FittedBox(
                                                                fit: BoxFit
                                                                    .scaleDown,
                                                                child: Text(
                                                                  "Note",
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                  ],
                                                ),
                                              ),
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
                                          ],
                                        ),
                                        MediaQuery(
                                          data: fixedTextScaleMediaQuery,
                                          child: Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8.0),
                                            child: Table(
                                              columnWidths: const {
                                                0: FlexColumnWidth(1),
                                                1: FlexColumnWidth(1),
                                                2: FlexColumnWidth(1),
                                                3: FlexColumnWidth(1),
                                              },
                                              defaultVerticalAlignment:
                                                  TableCellVerticalAlignment
                                                      .middle,
                                              children: [
                                                TableRow(
                                                  children: [
                                                    ProfileStatItem(
                                                        count:
                                                            views?.toString() ??
                                                                '0',
                                                        label: 'Views'),
                                                    ProfileStatItem(
                                                        count: submissions
                                                                ?.toString() ??
                                                            '0',
                                                        label: 'Submissions'),
                                                    ProfileStatItem(
                                                        count:
                                                            favs?.toString() ??
                                                                '0',
                                                        label: 'Favs'),
                                                    ProfileStatItem(
                                                        count:
                                                            recentWatchersCount
                                                                .toString(),
                                                        label: 'Watched'),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  pinned: false,
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
                                  return _ProfileTabKeepAlive(
                                    key: ValueKey(section),
                                    child: _buildLazySection(section),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                        if (showLoadingIndicator)
                          Container(
                            color: Colors.black.withValues(alpha: 1.0),
                            child: const Center(
                              child: PulsatingLoadingIndicator(
                                size: 88.0,
                                assetPath: 'assets/icons/fathemed.png',
                              ),
                            ),
                          ),
                        _buildEdgeBackSwipeOverlay(),
                        Positioned(
                          left: 16.0,
                          bottom: 16.0,
                          child: IgnorePointer(
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
                                  child: FloatingActionButton(
                                    heroTag: null,
                                    onPressed: _isDeletingSelectedShouts
                                        ? null
                                        : _confirmDeleteSelectedShouts,
                                    backgroundColor: Colors.red,
                                    tooltip: 'Delete Selected Shouts',
                                    child: _isDeletingSelectedShouts
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      Colors.white),
                                            ),
                                          )
                                        : const Icon(Icons.delete,
                                            color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  floatingActionButton: !isLoading
                      ? ValueListenableBuilder<bool>(
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
                                    duration: const Duration(milliseconds: 210),
                                    curve: Curves.easeInOut,
                                    child: child,
                                  ),
                                ),
                              ),
                            );
                          },
                          child: FloatingActionButton(
                            onPressed: () {
                              _scrollController.animateTo(
                                0.0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            },
                            backgroundColor: const Color(0xFFE09321),
                            child: const Icon(Icons.arrow_upward,
                                color: Colors.white),
                            tooltip: 'Scroll to Top',
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
      ),
    );
  }

  Widget _buildLazySection(ProfileSection section) {
    if (!_lazyLoadedSections.contains(section)) {
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
      case ProfileSection.Home:
        return _buildHomeSection();
      case ProfileSection.Gallery:
        return _buildGallerySection();
      case ProfileSection.Scraps:
        return _buildScrapsSection();
      case ProfileSection.Favs:
        return _buildFavoritesSection();
      case ProfileSection.Journals:
        return _buildJournalsSection();
    }
  }

  void _showEditProfileDialog() {
    _suppressNextRouteDetach = true;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Text(
            'Edit Profile',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchURL('https://www.furaffinity.net/controls/profile/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: const BorderSide(color: Color(0xFFE09321)),
                  ),
                  child: const Text(
                    "Profile Info",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchURL(
                        'https://www.furaffinity.net/controls/profilebanner/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: const BorderSide(color: Color(0xFFE09321)),
                  ),
                  child: const Text(
                    "Profile Banner",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchURL(
                        'https://www.furaffinity.net/controls/contacts/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: const BorderSide(color: Color(0xFFE09321)),
                  ),
                  child: const Text(
                    "Contacts & Social Media",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchURL('https://www.furaffinity.net/controls/avatar/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: const BorderSide(color: Color(0xFFE09321)),
                  ),
                  child: const Text(
                    "Avatar Management",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    ).whenComplete(() {
      _suppressNextRouteDetach = false;
    });
  }

  Widget _buildHomeSection() {
    return UserProfileHomeSection(
      hasRealUserProfile: hasRealUserProfile,
      userDescription: userDescription,
      webViewKey: _webViewKey,
      sanitizedUsername: sanitizedUsername,
      onDescriptionLongPressStart: _handleDescriptionLongPress,
      enableScrollPerformancePause:
          _webViewScrollOptimizationEnabled && _enableScrollWebViewPause,
      onWebViewLoaded: (loaded) {
        Future.delayed(Duration(milliseconds: 25), () {
          setState(() {
            _webViewLoaded = loaded;
          });
        });
      },
      featuredImageUrl: featuredImageUrl,
      featuredImageTitle: featuredImageTitle,
      featuredPostNumber: featuredPostNumber,
      onOpenPost: (context, imageUrl, uniqueNumber) {
        Navigator.push(
          context,
          OpenPost.route(
            imageUrl: imageUrl,
            uniqueNumber: uniqueNumber,
          ),
        );
      },
      userProfileImageUrl: userProfileImageUrl,
      userProfilePostNumber: userProfilePostNumber,
      userProfileTexts: userProfileTexts,
      isClassicMarkup: isClassicMarkup,
      acceptingTrades: acceptingTrades,
      acceptingCommissions: acceptingCommissions,
      onHandleFALink: _handleFALink,
      contactInformationLinks: contactInformationLinks,
      onLaunchUrl: _launchURL,
      recentWatchers: recentWatchers,
      recentWatchersCount: recentWatchersCount,
      recentlyWatched: recentlyWatched,
      recentlyWatchedCount: recentlyWatchedCount,
      shouts: shouts,
      isOwnProfile: isOwnProfile,
      isShoutSelectionMode: _isShoutSelectionMode,
      selectedShoutCount: _selectedShoutCount,
      currentShoutPage: currentShoutPage,
      totalShoutPages: totalShoutPages,
      isLoadingMoreShouts: isLoadingMoreShouts,
      onOpenPostShout: (context) async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostShoutScreen(username: sanitizedUsername),
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
      sanitizedUsername: sanitizedUsername,
      selectedFolderName: _selectedFolderName,
      selectedFolderUrl: _selectedFolderUrl,
      allFolders: _allFolders,
      onFolderSelected: _onFolderSelected,
      onFoldersParsed: _onFoldersParsed,
    );
  }

  /// Builds the Scraps section content.
  Widget _buildScrapsSection() {
    return UserProfileScrapsSection(
      sanitizedUsername: sanitizedUsername,
    );
  }

  Widget _buildFavoritesSection() {
    return UserProfileFavoritesSection(
      sanitizedUsername: sanitizedUsername,
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
      sanitizedUsername: sanitizedUsername,
      isOwnProfile: isOwnProfile,
      journalsKey: _journalsKey,
      onCreateJournalPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateJournalScreen(
              onJournalSubmitted: _refreshJournalsList,
            ),
          ),
        );
      },
    );
  }
}
