import 'dart:async';
import 'package:fanotifier/features/notifications/presentation/notification_navigation_provider.dart';
import 'package:fanotifier/features/browse/presentation/faimagegrid.dart';
import 'package:fanotifier/features/browse/presentation/filters_screen.dart';
import 'package:fanotifier/features/notes/domain/notes_repository.dart';
import 'package:fanotifier/features/notes/presentation/notesscreen.dart';
import 'package:fanotifier/features/notifications/presentation/notifications_screen.dart';
import 'package:fanotifier/features/search/presentation/search_screen.dart';
import 'package:fanotifier/features/submissions/presentation/submissions_screen.dart';
import 'package:fanotifier/features/upload/presentation/upload_submission.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:fanotifier/shared/fa/domain/fa_activities_polling_port.dart';
import 'package:fanotifier/features/notifications/presentation/fa_notification_service.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:badges/badges.dart' as badges;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/shared/utils/content_rating_filters.dart';
import 'package:fanotifier/shared/utils/external_link_launcher.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/drawer/presentation/drawer_user_controller.dart';
import 'package:fanotifier/shared/theme/app_theme.dart';
import 'package:fanotifier/shared/fa/domain/user_profile.dart';
import 'package:fanotifier/shared/fa/domain/notifications.dart';
import 'package:fanotifier/features/home/domain/home_login_webview_support.dart';
import 'package:fanotifier/features/home/domain/home_profile_repository.dart';
import 'package:fanotifier/features/home/domain/home_session_repository.dart';
import 'package:fanotifier/features/home/domain/home_start_screen_preference.dart';
import 'package:fanotifier/features/home/domain/home_start_screen_preference_repository.dart';
import 'package:fanotifier/features/auth/domain/startup_cloudflare_checker.dart';
import 'package:fanotifier/features/auth/presentation/cloudflare_check_screen.dart';
import 'package:fanotifier/features/drawer/domain/drawer_index.dart';
import 'package:fanotifier/features/notifications/presentation/notification_settings_provider.dart';
import 'package:fanotifier/features/notifications/domain/enabled_notification_items_count.dart';
import 'package:fanotifier/core/analytics/app_analytics.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/core/preferences/privacy_settings_provider.dart';
import 'package:fanotifier/features/settings/presentation/privacy_consent_screen.dart';

import '../../auth/domain/cloudflare_check_result.dart';

class HomeScreen extends StatefulWidget {
  final String? initialSearchQuery;

  const HomeScreen({this.initialSearchQuery, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const AssetImage _submissionsIconImage =
      AssetImage('assets/icons/submissions.png');
  static Future<void> _loginWebViewLoadQueue = Future<void>.value();

  UserProfile? _userProfile;
  bool isLoadingProfile = true;
  DrawerIndex drawerIndex = DrawerIndex.home;
  int _selectedIndex = 0;
  bool isCheckingLoginStatus = true;
  bool isLoggedIn = false;
  bool _sfwEnabled = true;
  final SfwModePreference _sfwModePreference = SfwModePreference();
  late final HomeSessionRepository _homeSessionRepository;
  late final HomeProfileRepository _homeProfileRepository;
  late final HomeLoginWebViewSupport _homeLoginWebViewSupport;
  late final HomeStartScreenPreferenceRepository
      _homeStartScreenPreferenceRepository;
  late final StartupCloudflareChecker _startupCloudflareChecker;
  late final FaActivitiesPollingPort _activitiesPolling;
  late final PrivacySettingsProvider _privacySettings;
  HomeStartScreenPreference _homeStartScreenPreference =
      HomeStartScreenPreference.browse;
  Future<void>? _homeStartPreferenceFuture;
  bool _homeStartPreferenceLoaded = false;
  bool _didOpenStartupProfile = false;
  bool _isOpeningStartupProfile = false;
  String? _startupHomeHtml;
  final Set<int> _loadedHomeIndexes = <int>{};
  bool _startupWarmupScheduled = false;

  bool _profileFetched = false;

  Timer? _elementCheckTimer;
  DateTime? _firstTimeElementFound;

  final GlobalKey<DrawerUserControllerState> _drawerKey =
      GlobalKey<DrawerUserControllerState>();

  Map<String, String> browseFilters =
      ContentRatingFilters.defaultBrowseFilters(sfwEnabled: true);

  Map<String, String> searchFilters =
      ContentRatingFilters.defaultSearchFilters(sfwEnabled: true);

  final ValueNotifier<Map<String, List<Map<String, String>>>>
      filterOptionsNotifier = ValueNotifier({});

  InAppWebViewController? _webViewController;

  Timer? _dataRefreshTimer;

  int _unreadCount = 0;
  Timer? _foregroundFetchTimer;

  /// Initial section for NotificationsScreen.
  String? _notificationsInitialSection;

  final GlobalKey<SubmissionsScreenState> _submissionsKey =
      GlobalKey<SubmissionsScreenState>();
  final GlobalKey<FAImageGridState> _browseKey = GlobalKey<FAImageGridState>();
  final GlobalKey<SearchScreenState> _searchKey =
      GlobalKey<SearchScreenState>();
  final GlobalKey<NotesScreenState> _notesKey = GlobalKey<NotesScreenState>();
  late final NotificationNavigationProvider _navProvider;

  // Gate login SnackBar to only show once per real login
  bool _loginSnackShownThisRun = false;
  bool _pendingLoginSnack = false;

  @override
  void initState() {
    super.initState();
    _homeSessionRepository = context.read<HomeSessionRepository>();
    _homeProfileRepository = context.read<HomeProfileRepository>();
    _homeLoginWebViewSupport = context.read<HomeLoginWebViewSupport>();
    _homeStartScreenPreferenceRepository =
        context.read<HomeStartScreenPreferenceRepository>();
    _startupCloudflareChecker = context.read<StartupCloudflareChecker>();
    _activitiesPolling = context.read<FaActivitiesPollingPort>();
    _privacySettings = context.read<PrivacySettingsProvider>();
    _navProvider =
        Provider.of<NotificationNavigationProvider>(context, listen: false);
    _navProvider.addListener(_handleNavProviderChange);

    _homeStartPreferenceFuture = _loadHomeStartScreenPreference();
    _initializeAndLoadLoginState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logSelectedHomeScreen();
      if (widget.initialSearchQuery != null &&
          widget.initialSearchQuery!.isNotEmpty) {
        _triggerSearch(widget.initialSearchQuery!);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(precacheImage(_submissionsIconImage, context));
  }

  @override
  void dispose() {
    _dataRefreshTimer?.cancel();
    _foregroundFetchTimer?.cancel();
    _elementCheckTimer?.cancel();
    _webViewController = null;
    filterOptionsNotifier.dispose();
    _navProvider.removeListener(_handleNavProviderChange);
    super.dispose();
  }

  void _handleNavProviderChange() {
    if (!mounted) return;

    final int? next = _navProvider.takeTargetIndex();
    if (next == null) return;
    if (next == _selectedIndex) return;

    setState(() {
      _selectedIndex = next;
      _loadedHomeIndexes.add(next);
    });
    _logSelectedHomeScreen();
  }

  Future<void> _loadHomeStartScreenPreference() async {
    final preference = await _homeStartScreenPreferenceRepository.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _homeStartScreenPreference = preference;
      if (preference == HomeStartScreenPreference.submissions &&
          _selectedIndex == 0) {
        _selectedIndex = 2;
      }
      _loadedHomeIndexes.add(_selectedIndex);
      _homeStartPreferenceLoaded = true;
    });

    _maybeOpenStartupProfile();
    _logSelectedHomeScreen();
  }

  Future<void> _initializeAndLoadLoginState() async {
    await _privacySettings.load();
    await _loadSfwEnabled();
    await _loadLoginState();
    await (_homeStartPreferenceFuture ?? Future<void>.value());
    if (isLoggedIn) {
      await _loadCachedUserProfile();
    }
    final canProceed = await _runStartupCloudflareCheck();
    if (!canProceed) {
      setState(() {
        isCheckingLoginStatus = false;
        isLoggedIn = false;
      });
      return;
    }

    if (isLoggedIn) {
      await _setCookiesFromPrefs();
      _startActivitiesPolling(triggerImmediate: false);

      setState(() {
        isCheckingLoginStatus = false;
      });

      if (!_profileFetched) {
        _profileFetched = true;
        final profileFuture = _fetchUserProfile();
        if (_homeStartScreenPreference == HomeStartScreenPreference.profile &&
            _userProfile == null) {
          await profileFuture;
        } else {
          unawaited(profileFuture);
        }
      }
    } else {
      setState(() {
        isCheckingLoginStatus = false;
      });
    }
  }

  Future<bool> _runStartupCloudflareCheck() async {
    final check = await _startupCloudflareChecker.checkHome();
    _startupHomeHtml = isLoggedIn ? check.homeHtml : null;
    if (!check.needsChallenge) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return false;
    }

    final result = await Navigator.of(context).push<CloudflareCheckResult>(
      MaterialPageRoute<CloudflareCheckResult>(
        settings:
            const AnalyticsRouteSettings(AppScreens.cloudflareCheck),
        builder: (_) => const CloudflareCheckScreen(),
      ),
    );
    return result?.passed == true;
  }

  void _startActivitiesPolling({required bool triggerImmediate}) {
    try {
      final svc = Provider.of<FANotificationService>(context, listen: false);
      _activitiesPolling.start(faNotificationService: svc);
      if (triggerImmediate) {
        unawaited(_activitiesPolling.triggerNow(
          resetTimer: true,
          source: 'login_established',
        ));
      }
    } catch (_) {}
  }

  Future<void> _loadCachedUserProfile() async {
    final cachedProfile = await _homeSessionRepository.loadCachedUserProfile();
    if (!mounted || cachedProfile == null) return;
    setState(() {
      _userProfile = cachedProfile;
      isLoadingProfile = false;
    });
    _maybeOpenStartupProfile();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final startupHomeHtml = _startupHomeHtml;
      _startupHomeHtml = null;
      UserProfile? profile = await _homeProfileRepository.fetchUserProfile(
        homeHtml: startupHomeHtml,
      );
      if (profile != null) {
        await _homeSessionRepository.saveCachedUserProfile(profile);
      }
      if (!mounted) return;
      setState(() {
        if (profile != null) {
          _userProfile = profile;
        }
        isLoadingProfile = false;
      });
      _maybeOpenStartupProfile();
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
      if (!mounted) return;
      setState(() {
        isLoadingProfile = false;
      });
    }
  }

  Future<void> _saveLoginState(bool value) async {
    await _homeSessionRepository.saveIsLoggedIn(value);
  }

  Future<void> _loadLoginState() async {
    bool savedLoginState = await _homeSessionRepository.loadIsLoggedIn();
    setState(() {
      isLoggedIn = savedLoginState;
      if (!savedLoginState) {
        _didOpenStartupProfile = false;
      }
    });
  }

  Future<void> _loadSfwEnabled() async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    setState(() {
      _sfwEnabled = sfwEnabled;
      browseFilters =
          ContentRatingFilters.defaultBrowseFilters(sfwEnabled: sfwEnabled);
      searchFilters =
          ContentRatingFilters.defaultSearchFilters(sfwEnabled: sfwEnabled);
    });
  }

  void openNotificationsWithSection(String section) {
    setState(() {
      _selectedIndex = 3;
      _loadedHomeIndexes.add(3);
      _notificationsInitialSection = section;
    });
    appAnalytics.logScreen(AppScreens.notificationSection(section));
  }

  int _getNotificationsEnabledSum(
    NotificationSettingsProvider settings,
    FANotificationService faNotificationService,
  ) {
    return enabledNotificationItemsCount(
      sections: faNotificationService.sections,
      watchersEnabled: settings.watchersEnabled,
      journalsEnabled: settings.journalsEnabled,
      commentsEnabled: settings.commentsEnabled,
      favoritesEnabled: settings.favoritesEnabled,
      shoutsEnabled: settings.shoutsEnabled,
    );
  }

  void _onNotificationsUpdated(Notifications _) {
    setState(() {});
  }

  void _onBottomNavigationItemTapped(int index) {
    _drawerKey.currentState?.closeDrawer();

    if (index == _selectedIndex) {
      unawaited(_scrollToTopForIndex(index));
      return;
    }

    setState(() {
      _selectedIndex = index;
      _loadedHomeIndexes.add(index);
      if (index != 3) {
        _notificationsInitialSection = null;
      }
    });
    _logSelectedHomeScreen();
  }

  void _logSelectedHomeScreen() {
    final screen = switch (_selectedIndex) {
      0 => isLoggedIn ? AppScreens.browse : AppScreens.login,
      1 => AppScreens.search,
      2 => AppScreens.submissions,
      3 => AppScreens.notifications,
      4 => AppScreens.notesInbox,
      _ => AppScreens.browse,
    };
    appAnalytics.logScreen(screen);
  }

  Future<void> _scrollToTopForIndex(int index) async {
    switch (index) {
      case 0:
        await _browseKey.currentState?.scrollToTop();
        return;
      case 1:
        await _searchKey.currentState?.scrollToTop();
        return;
      case 2:
        await _submissionsKey.currentState?.scrollToTop();
        return;
      case 4:
        await _notesKey.currentState?.scrollToTop();
        return;
      default:
        return;
    }
  }

  void _triggerSearch(String query) {
    setState(() {
      _selectedIndex = 1;
      _loadedHomeIndexes.add(1);
    });
    _logSelectedHomeScreen();
  }

  void _onNoteCounterTap() {
    _changeIndex(DrawerIndex.notes);
  }

  bool get _shouldHoldForStartupProfile {
    if (_homeStartScreenPreference != HomeStartScreenPreference.profile ||
        !isLoggedIn ||
        _selectedIndex != 0) {
      return false;
    }

    if (_didOpenStartupProfile) {
      return false;
    }

    final profile = _userProfile;
    return profile == null || userProfileRouteNickname(profile) == null;
  }

  void _maybeOpenStartupProfile() {
    if (!mounted ||
        _isOpeningStartupProfile ||
        _didOpenStartupProfile ||
        !_privacySettings.consentShown ||
        _homeStartScreenPreference != HomeStartScreenPreference.profile ||
        _selectedIndex != 0) {
      return;
    }

    final profile = _userProfile;
    if (profile == null) {
      return;
    }

    final lowercaseNickname = userProfileRouteNickname(profile);
    if (lowercaseNickname == null) return;
    debugPrint("Extracted nickname: $lowercaseNickname");

    setState(() {
      _didOpenStartupProfile = true;
      _isOpeningStartupProfile = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).push(
        UserProfileScreen.route<void>(
          nickname: lowercaseNickname,
          instant: true,
        ),
      ).whenComplete(() {
        if (!mounted) {
          return;
        }
        setState(() {
          _isOpeningStartupProfile = false;
        });
      });
    });
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: _homeLoginWebViewSupport.assets.initialHtml,
        baseUrl: WebUri('about:blank'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
        supportZoom: true,
      ),
      onWebViewCreated: (InAppWebViewController controller) {
        _webViewController = controller;
        unawaited(_loadInitialLoginUrl(controller));
      },
      onLoadStart: (InAppWebViewController controller, WebUri? url) async {
        debugPrint(
            'WebView Loading Started: ${url?.toString() ?? "Unknown URL"}');
        _cancelStabilityTimer();
        if (_homeLoginWebViewSupport.isLoginUrl(url?.toString())) {
          await _injectLoginCss();
        }
      },
      onReceivedHttpError: (InAppWebViewController controller,
          WebResourceRequest request, WebResourceResponse response) async {
        debugPrint(
            "Received HTTP ${response.statusCode} error: ${response.reasonPhrase}");
        if (response.statusCode == 403) {
          _cancelStabilityTimer();
          return;
        }
      },
      onLoadStop: (controller, url) async {
        final pageUrl = url?.toString() ?? '';
        debugPrint('Load stopped at: $pageUrl');
        if (_homeLoginWebViewSupport.isLoginUrl(url?.toString())) {
          await _injectLoginCss();
        }

        if (_homeLoginWebViewSupport.isAuthenticatedHomeUrl(pageUrl)) {
          if (await _homeSessionRepository.hasWebViewAuthCookie()) {
            await _homeSessionRepository.saveCookiesFromWebView();

            // Read previous login state BEFORE we set true
            final wasLoggedIn =
                await _homeSessionRepository.loadIsLoggedIn();

            await _saveLoginState(true);
            setState(() {
              isLoggedIn = true;
              _webViewController = null;
            });
            _startActivitiesPolling(triggerImmediate: false);

            await _setSfwCookieToNSFW();

            _cancelStabilityTimer();

            if (!_profileFetched) {
              _profileFetched = true;
              unawaited(_fetchUserProfile());
            }

            if (!wasLoggedIn && !_loginSnackShownThisRun && mounted) {
              _loginSnackShownThisRun = true;
              if (_privacySettings.loaded && !_privacySettings.consentShown) {
                _pendingLoginSnack = true;
              } else {
                _showLoginSuccessSnackBar();
              }
            }
          } else {
            if (!isLoggedIn) {
              _startElementStabilityCheck();
            }
          }
        } else {
          _cancelStabilityTimer();
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        var uri = navigationAction.request.url;
        debugPrint("Navigating to: $uri");
        if (_homeLoginWebViewSupport.isPasswordRecoveryUrl(uri)) {
          debugPrint("Password recovery URL detected.");
          if (await tryLaunchExternalUri(uri!)) {
            debugPrint('Opened Password Recovery in external browser.');
            return NavigationActionPolicy.CANCEL;
          } else {
            debugPrint('Could not launch $uri');
            if (!mounted) return NavigationActionPolicy.CANCEL;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Could not open link. Please try again.')),
            );
          }
        }
        return NavigationActionPolicy.ALLOW;
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint("WebView Console Message: ${consoleMessage.message}");
      },
    );
  }

  Future<void> _loadInitialLoginUrl(InAppWebViewController controller) {
    final next = _loginWebViewLoadQueue.catchError((_) {}).then((_) async {
      final loadSlot =
          await _homeLoginWebViewSupport.waitForAvailableLoadSlot();
      if (!mounted || isLoggedIn || _webViewController != controller) {
        return;
      }
      await loadSlot.recordLoadStart();
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(_homeLoginWebViewSupport.loginUrl)),
      );
    });
    _loginWebViewLoadQueue = next.catchError((_) {});
    return next;
  }

  void _startElementStabilityCheck() {
    _cancelStabilityTimer();
    _elementCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_webViewController == null) return;

      String? html = await _webViewController!
          .evaluateJavascript(
            source: _homeLoginWebViewSupport.assets.outerHtmlScript,
          );

      final elementFound =
          _homeLoginWebViewSupport.hasLoggedInHomeElement(html);

      if (elementFound) {
        if (_firstTimeElementFound == null) {
          _firstTimeElementFound = DateTime.now();
        } else {
          final elapsed = DateTime.now().difference(_firstTimeElementFound!);
          if (elapsed >= const Duration(seconds: 1)) {
            setState(() {
              isLoggedIn = true;
              _webViewController = null;
            });
            _cancelStabilityTimer();

            await _homeSessionRepository.saveCookiesFromWebView();

            final wasLoggedIn =
                await _homeSessionRepository.loadIsLoggedIn();

            await _saveLoginState(true);
            _startActivitiesPolling(triggerImmediate: false);
            await _setSfwCookieToNSFW();

            if (!_profileFetched) {
              _profileFetched = true;
              unawaited(_fetchUserProfile());
            }

            if (!wasLoggedIn && !_loginSnackShownThisRun && mounted) {
              _loginSnackShownThisRun = true;
              if (_privacySettings.loaded && !_privacySettings.consentShown) {
                _pendingLoginSnack = true;
              } else {
                _showLoginSuccessSnackBar();
              }
            }
          }
        }
      } else {
        _firstTimeElementFound = null;
      }
    });
  }

  void _cancelStabilityTimer() {
    _elementCheckTimer?.cancel();
    _elementCheckTimer = null;
    _firstTimeElementFound = null;
  }

  void _showLoginSuccessSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged in successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _flushPendingLoginSnack() {
    if (!mounted || !_pendingLoginSnack) return;
    _pendingLoginSnack = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showLoginSuccessSnackBar();
    });
  }

  void _scheduleStartupWarmup() {
    if (_startupWarmupScheduled || !isLoggedIn || !_homeStartPreferenceLoaded) {
      return;
    }
    _startupWarmupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_warmStartupScreens());
    });
  }

  Future<void> _warmStartupScreens() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || !isLoggedIn) return;

    await _activitiesPolling.triggerNow(
      resetTimer: true,
      source: 'startup_warmup',
    );

    final order = <int>[
      _selectedIndex,
      0,
      2,
      4,
      3,
    ];
    final seen = <int>{};
    for (final index in order) {
      if (!seen.add(index)) continue;
      if (!mounted || !isLoggedIn) return;
      if (!_loadedHomeIndexes.contains(index)) {
        setState(() {
          _loadedHomeIndexes.add(index);
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
  }

  Widget _buildMainAppScreen(BuildContext context) {
    if (!_homeStartPreferenceLoaded || !_privacySettings.loaded) {
      return const Center(
          child: PulsatingLoadingIndicator(
              size: 108.0, assetPath: 'assets/icons/fathemed.png'));
    }
    if (!_privacySettings.consentShown) {
      return PrivacyConsentScreen(
        onCompleted: () {
          if (!mounted) return;
          setState(() {});
          _flushPendingLoginSnack();
        },
      );
    }
    if (_shouldHoldForStartupProfile) {
      return const Center(
          child: PulsatingLoadingIndicator(
              size: 108.0, assetPath: 'assets/icons/fathemed.png'));
    }
    _scheduleStartupWarmup();
    final userProfile = _userProfile ??
        UserProfile(
          username: 'Username',
          profileImageUrl: '',
        );
    return DrawerUserController(
      key: _drawerKey,
      screenIndex: drawerIndex,
      drawerWidth: MediaQuery.sizeOf(context).width * 0.75,
      onDrawerCall: (DrawerIndex drawerIndexdata) {
        _changeIndex(drawerIndexdata);
      },
      screenView: _buildSelectedScreen(),
      onLogout: _logout,
      userProfile: userProfile,
      onNoteCounterTap: _onNoteCounterTap,
      onNotesCountChanged: (int count) {
        setState(() {
          _unreadCount = count;
        });
      },
      onNotificationsUpdated: _onNotificationsUpdated,
      onBadgeTap: openNotificationsWithSection,
      isUserProfileLoading: isLoadingProfile,
      enableSwipe: _selectedIndex != 9,
    );
  }

  Future<void> _setCookiesFromPrefs() async {
    await _homeSessionRepository.setStoredCookies();
  }

  Widget _buildHomeStackChild(int index, Widget Function() builder) {
    if (index == _selectedIndex || _loadedHomeIndexes.contains(index)) {
      return builder();
    }
    return const SizedBox.shrink();
  }

  Widget _buildSelectedScreen() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        _buildHomeStackChild(
          0,
          () => Scaffold(
            appBar: AppBar(
              title: const Text('Browse'),
              centerTitle: true,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: () async {
                      final updatedFilters =
                          await Navigator.push<Map<String, String>>(
                        context,
                        MaterialPageRoute(
                          settings: const AnalyticsRouteSettings(
                            AppScreens.browseFilters,
                          ),
                          builder: (context) => FiltersScreen(
                            selectedFilters: browseFilters,
                            sfwEnabled: _sfwEnabled,
                          ),
                        ),
                      );
                      if (updatedFilters != null) {
                        setState(() {
                          browseFilters =
                              ContentRatingFilters.normalizeBrowseFilters(
                            updatedFilters,
                            sfwEnabled: _sfwEnabled,
                          );
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            body: FAImageGrid(
              key: _browseKey,
              selectedFilters: browseFilters,
            ),
          ),
        ),
        _buildHomeStackChild(
          1,
          () => SearchScreen(
            key: _searchKey,
            searchFilters: searchFilters,
            sfwEnabled: _sfwEnabled,
            onFilterUpdated: (updatedSearchFilters) {
              setState(() {
                searchFilters = ContentRatingFilters.normalizeSearchFilters(
                  updatedSearchFilters,
                  sfwEnabled: _sfwEnabled,
                );
              });
            },
          ),
        ),
        _buildHomeStackChild(
          2,
          () => SubmissionsScreen(key: _submissionsKey),
        ),
        _buildHomeStackChild(
          3,
          () => NotificationsScreen(
            drawerKey: _drawerKey,
            key: ValueKey(_notificationsInitialSection),
            initialSection: _notificationsInitialSection,
          ),
        ),
        _buildHomeStackChild(
          4,
          () => NotesScreen(
            drawerKey: _drawerKey,
            repositoryFactory: context.read<NotesRepositoryFactory>(),
            key: _notesKey,
          ),
        ),
      ],
    );
  }

  void _changeIndex(DrawerIndex indexScreen) {
    if (indexScreen == DrawerIndex.upload) {
      setState(() {
        drawerIndex = indexScreen;
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          settings:
              const AnalyticsRouteSettings(AppScreens.uploadSubmission),
          builder: (context) => const UploadSubmissionScreen(),
        ),
      ).then((_) {
        if (!mounted) return;
        setState(() {
          drawerIndex = DrawerIndex.home;
          _selectedIndex = 0;
          _loadedHomeIndexes.add(0);
        });
        _logSelectedHomeScreen();
      });
    } else {
      setState(() {
        drawerIndex = indexScreen;
        switch (indexScreen) {
          case DrawerIndex.home:
            _selectedIndex = 0;
            _loadedHomeIndexes.add(0);
            break;
          case DrawerIndex.submissions:
            _selectedIndex = 2;
            _loadedHomeIndexes.add(2);
            _submissionsKey.currentState?.refreshSubmissionsManually();
            break;
          case DrawerIndex.notes:
            _selectedIndex = 4;
            _loadedHomeIndexes.add(4);
            break;
          case DrawerIndex.notifications:
            _selectedIndex = 3;
            _loadedHomeIndexes.add(3);
            break;
          default:
            debugPrint("Unhandled DrawerIndex: $indexScreen");
            _selectedIndex = 0;
            _loadedHomeIndexes.add(0);
            break;
        }
      });
      _logSelectedHomeScreen();
      if (drawerIndex != DrawerIndex.home) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            drawerIndex = DrawerIndex.home;
          });
        });
      }
    }
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
          child: PulsatingLoadingIndicator(
              size: 108.0, assetPath: 'assets/icons/fathemed.png')),
    );

    try {
      _activitiesPolling.stop();
      await _homeSessionRepository.clearLocalSession();

      if (!mounted) return;
      final faNotificationService =
          Provider.of<FANotificationService>(context, listen: false);
      faNotificationService.clearAllNotifications();

      setState(() {
        isLoggedIn = false;
        _userProfile = null;
        _unreadCount = 0;
        isLoadingProfile = false;
        drawerIndex = DrawerIndex.home;
        _selectedIndex = 0;
        _loadedHomeIndexes
          ..clear()
          ..add(0);
        _startupWarmupScheduled = false;
        _homeStartPreferenceLoaded = true;
        _didOpenStartupProfile = false;
        _isOpeningStartupProfile = false;
      });

      Navigator.of(context).pop();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (BuildContext context) => const HomeScreen()),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      debugPrint('[Logout] Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during logout: $e')),
      );
    }
  }

  Future<void> _injectLoginCss() async {
    await _webViewController?.injectCSSCode(
      source: _homeLoginWebViewSupport.assets.css,
    );
  }

  Future<void> _setSfwCookieToNSFW() async {
    await _homeSessionRepository.setSfwCookieToNsfw();
  }

  Future<void> _onRequestCloseApp() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final confirmed = await ConfirmCloseDialog.show(
      context,
      title: 'Confirm app closing',
      message: 'Are you sure you want to close the app?',
    );

    if (confirmed && mounted) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<NotificationSettingsProvider, FANotificationService>(
      builder: (context, settings, faNotificationService, child) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, dynamic result) {
            if (didPop) return;
            // On Notes tab: first back closes selection mode if active
            if (_selectedIndex == 4) {
              final notesState = _notesKey.currentState;
              if (notesState != null && notesState.isInSelectionMode) {
                notesState.exitSelectionMode();
                return;
              }
            }
            _onRequestCloseApp();
          },
          child: Scaffold(
            body: isLoggedIn ? _buildMainAppScreen(context) : _buildWebView(),
            bottomNavigationBar:
                _shouldHoldForStartupProfile || !_privacySettings.consentShown
                    ? null
                    : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(
                        height: 1.0,
                        color: Color(0xFF111111),
                        thickness: 3.0,
                      ),
                      Theme(
                        data: Theme.of(context).copyWith(
                          splashFactory: NoSplash.splashFactory,
                        ),
                        child: BottomNavigationBar(
                          type: BottomNavigationBarType.shifting,
                          items: [
                            BottomNavigationBarItem(
                              icon: const Icon(Icons.home),
                              label: 'Browse',
                              backgroundColor: AppTheme.background,
                            ),
                            BottomNavigationBarItem(
                              icon: const Icon(Icons.search),
                              label: 'Search',
                              backgroundColor: AppTheme.background,
                            ),
                            BottomNavigationBarItem(
                              icon: Image(
                                image: _submissionsIconImage,
                                width: 27,
                                height: 27,
                                color: Colors.grey,
                                gaplessPlayback: true,
                              ),
                              activeIcon: Image(
                                image: _submissionsIconImage,
                                width: 27,
                                height: 27,
                                color: const Color(0xFFE09321),
                                gaplessPlayback: true,
                              ),
                              label: 'Submissions',
                              backgroundColor: AppTheme.background,
                            ),
                            BottomNavigationBarItem(
                              icon: badges.Badge(
                                badgeContent: SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: Center(
                                    child: FittedBox(
                                      child: Text(
                                        _getNotificationsEnabledSum(
                                                settings, faNotificationService)
                                            .toString(),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                                showBadge: _getNotificationsEnabledSum(
                                        settings, faNotificationService) >
                                    0,
                                position: badges.BadgePosition.topEnd(
                                    top: -5, end: -7),
                                badgeStyle: const badges.BadgeStyle(
                                  padding: EdgeInsets.all(2),
                                  badgeColor: Colors.red,
                                ),
                                child: const Icon(Icons.notifications),
                              ),
                              label: 'Notifications',
                              backgroundColor: AppTheme.background,
                            ),
                            BottomNavigationBarItem(
                              icon: badges.Badge(
                                badgeContent: SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: Center(
                                    child: FittedBox(
                                      child: Text(
                                        _unreadCount.toString(),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                                showBadge: _unreadCount > 0,
                                position: badges.BadgePosition.topEnd(
                                    top: -5, end: -7),
                                badgeStyle: const badges.BadgeStyle(
                                  padding: EdgeInsets.all(2),
                                  badgeColor: Colors.red,
                                ),
                                child: const Icon(Icons.mail),
                              ),
                              label: 'Notes',
                              backgroundColor: AppTheme.background,
                            ),
                          ],
                          currentIndex: _selectedIndex,
                          selectedItemColor: const Color(0xFFE09321),
                          unselectedItemColor: Colors.grey,
                          onTap: _onBottomNavigationItemTapped,
                          showSelectedLabels: true,
                          showUnselectedLabels: false,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
