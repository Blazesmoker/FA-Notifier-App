import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:FANotifier/providers/NotificationNavigationProvider.dart';
import 'package:FANotifier/screens/faimagegrid.dart';
import 'package:FANotifier/screens/filters_screen.dart';
import 'package:FANotifier/screens/notesscreen.dart';
import 'package:FANotifier/screens/notifications_provider.dart';
import 'package:FANotifier/screens/notifications_screen.dart';
import 'package:FANotifier/screens/search_screen.dart';
import 'package:FANotifier/screens/submissions_screen.dart';
import 'package:FANotifier/screens/upload_submission.dart';
import 'package:FANotifier/services/fa_notification_service.dart';
import 'package:FANotifier/services/notes_refresh_service.dart';
import 'package:FANotifier/services/notification_refresh_service.dart';
import 'package:FANotifier/widgets/PulsatingLoadingIndicator.dart';
import 'package:badges/badges.dart' as badges;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'custom_drawer/drawer_user_controller.dart';
import 'app_theme.dart';
import 'model/user_profile.dart';
import 'model/notifications.dart';
import 'services/fa_service.dart';
import 'enums/drawer_index.dart';
import 'services/notification_service.dart';
import 'utils.dart';
import 'utils/message_storage.dart';
import 'providers/notification_settings_provider.dart';

class HomeScreen extends StatefulWidget {
  final String? initialSearchQuery;

  const HomeScreen({this.initialSearchQuery, super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UserProfile? _userProfile;
  bool isLoadingProfile = true;
  DrawerIndex drawerIndex = DrawerIndex.HOME;
  int _selectedIndex = 0;
  bool isCheckingLoginStatus = true;
  bool isLoggedIn = false;
  bool _forceNotesRefresh = false;

  bool _profileFetched = false;

  Timer? _elementCheckTimer;
  DateTime? _firstTimeElementFound;
  bool _mainPageStable = false;

  int _previousSum = 0;

  final GlobalKey<DrawerUserControllerState> _drawerKey =
  GlobalKey<DrawerUserControllerState>();

  Map<String, String> browseFilters = {
    'cat': '1',
    'atype': '1',
    'species': '1',
    'gender': '0',
  };

  Map<String, String> searchFilters = {
    'order-by': 'relevancy',
    'order-direction': 'desc',
    'range': '5years',
    'mode': 'extended',
    'rating-general': '1',
    'rating-mature': '1',
    'rating-adult': '1',
    'type-art': '1',
    'type-music': '1',
    'type-flash': '1',
    'type-story': '1',
    'type-photo': '1',
    'type-poetry': '1',
    'range_from': '',
    'range_to': '',
  };

  final ValueNotifier<Map<String, List<Map<String, String>>>> filterOptionsNotifier =
  ValueNotifier({});

  InAppWebViewController? _webViewController;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
        accountName: 'flutter_secure_storage_service',
        accessibility: KeychainAccessibility.first_unlock),
  );

  final String loginUrl = 'https://www.furaffinity.net/login';
  final String postLoginUrl = 'https://www.furaffinity.net/';
  final FaService _faService = FaService();
  Timer? _dataRefreshTimer;

  int _unreadCount = 0;
  Timer? _foregroundFetchTimer;

  Notifications? _currentNotifications;

  /// Initial section for NotificationsScreen.
  String? _notificationsInitialSection;

  final GlobalKey<SubmissionsScreenState> _submissionsKey =
  GlobalKey<SubmissionsScreenState>();
  final GlobalKey<FAImageGridState> _browseKey = GlobalKey<FAImageGridState>();
  final GlobalKey<SearchScreenState> _searchKey = GlobalKey<SearchScreenState>();
  final GlobalKey<NotesScreenState> _notesKey = GlobalKey<NotesScreenState>();

  // Gate login SnackBar to only show once per real login
  bool _loginSnackShownThisRun = false;

  @override
  void initState() {
    super.initState();

    _initializeAndLoadLoginState();
    _handlePendingNavigation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialSearchQuery != null &&
          widget.initialSearchQuery!.isNotEmpty) {
        _triggerSearch(widget.initialSearchQuery!);
      }
    });

    final navProvider =
    Provider.of<NotificationNavigationProvider>(context, listen: false);
    navProvider.addListener(_handleNavProviderChange);
  }

  @override
  void dispose() {
    _dataRefreshTimer?.cancel();
    _foregroundFetchTimer?.cancel();
    _elementCheckTimer?.cancel();
    filterOptionsNotifier.dispose();
    final navProvider =
    Provider.of<NotificationNavigationProvider>(context, listen: false);
    navProvider.removeListener(_handleNavProviderChange);
    super.dispose();
  }

  void _handleNavProviderChange() {
    if (!mounted) return;

    final navProvider =
    Provider.of<NotificationNavigationProvider>(context, listen: false);
    final int? next = navProvider.takeTargetIndex();
    if (next == null) return;
    if (next == _selectedIndex) return;

    setState(() {
      _selectedIndex = next;
      if (next == 4) _forceNotesRefresh = true;
    });
  }

  Future<void> _handlePendingNavigation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String? pendingPayload = prefs.getString('pending_navigation');
    if (pendingPayload == null) return;
    if (pendingPayload.isEmpty) {
      await prefs.remove('pending_navigation');
      return;
    }

    final navProvider =
    Provider.of<NotificationNavigationProvider>(context, listen: false);
    final bool isNotes = pendingPayload.startsWith('note_') ||
        pendingPayload.contains('DrawerIndex.Notes') ||
        pendingPayload == 'note_native';
    final bool isActivities = pendingPayload.startsWith('activity_') ||
        pendingPayload.contains('DrawerIndex.Notifications') ||
        pendingPayload == 'activity_native';

    if (isNotes) {
      navProvider.setTargetIndex(4);
      setState(() => _forceNotesRefresh = true); // keep if you rely on it elsewhere

      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotesRefreshService().triggerRefresh();
        debugPrint("NOTES REFRESH TRIGGERED_home_postframe");
      });
    } else if (isActivities) {
      navProvider.setTargetIndex(3);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationRefreshService().triggerRefresh();
        debugPrint("ACTIVITIES REFRESH TRIGGERED_home_postframe");
      });
    }

    await prefs.remove('pending_navigation');
  }

  Future<void> _initializeAndLoadLoginState() async {
    await _loadLoginState();
    if (isLoggedIn) {
      await _setCookiesFromPrefs();
      bool validSession = await _validateSession();

      setState(() {
        isCheckingLoginStatus = false;
      });

      if (!_profileFetched) {
        await _fetchUserProfile();
        _profileFetched = true;
      }
    } else {
      setState(() {
        isCheckingLoginStatus = false;
      });
    }
  }


  Future<bool> _validateSession() async {
    try {
      final profile = await _faService.fetchUserProfile();
      return profile != null;
    } on SocketException catch (_) {
      debugPrint('[Session] SocketException → assume still logged in');
      return true;
    } on TimeoutException catch (_) {
      debugPrint('[Session] TimeoutException → assume still logged in');
      return true;
    } catch (e) {
      debugPrint('[Session] Unknown error "$e" → assume still logged in');
      return true;
    }
  }

  Future<void> _fetchUserProfile() async {
    try {
      UserProfile? profile =
      await _faService.fetchUserProfile(context: context);
      setState(() {
        _userProfile = profile;
        isLoadingProfile = false;
      });
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
      setState(() {
        isLoadingProfile = false;
      });
    }
  }

  Future<void> _saveLoginState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', value);
  }

  Future<void> _loadLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    bool savedLoginState = prefs.getBool('isLoggedIn') ?? false;
    setState(() {
      isLoggedIn = savedLoginState;
    });
  }

  void openNotificationsWithSection(String section) {
    setState(() {
      _selectedIndex = 3;
      _notificationsInitialSection = section;
    });
  }

  int _getNotificationsEnabledSum(
      NotificationSettingsProvider settings,
      FANotificationService faNotificationService,
      ) {
    _previousSum = faNotificationService.sections.fold<int>(
      0,
          (sum, s) => sum + s.items.length,
    );

    int visible = 0;
    for (final section in faNotificationService.sections) {
      final title = section.title;
      final n = section.items.length;
      if (title.contains('Watches') && settings.watchersEnabled) visible += n;
      if (title.contains('Journals') && settings.journalsEnabled) visible += n;
      if (title.contains('Submission Comments') &&
          settings.commentsEnabled) visible += n;
      if (title.contains('Journal Comments') && settings.commentsEnabled) visible += n;
      if (title.contains('Favorites') && settings.favoritesEnabled) visible += n;
      if (title.contains('Shouts') && settings.shoutsEnabled) visible += n;
    }
    return visible;
  }

  void _onNotificationsUpdated(Notifications notifications) {
    setState(() {
      _currentNotifications = notifications;
    });
  }

  void _onBottomNavigationItemTapped(int index) {
    _drawerKey.currentState?.closeDrawer();

    if (index == _selectedIndex) {
      unawaited(_scrollToTopForIndex(index));
      return;
    }

    setState(() {
      _selectedIndex = index;
      if (index != 3) {
        _notificationsInitialSection = null;
      }
    });
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
    });
  }

  void _onNoteCounterTap() {
    _changeIndex(DrawerIndex.Notes);
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(loginUrl)),
      initialOptions: InAppWebViewGroupOptions(
        crossPlatform: InAppWebViewOptions(
          javaScriptEnabled: true,
          useShouldOverrideUrlLoading: true,
          mediaPlaybackRequiresUserGesture: false,
          clearCache: false,
          supportZoom: true,
        ),
      ),
      onWebViewCreated: (InAppWebViewController controller) {
        _webViewController = controller;
      },
      onLoadStart: (InAppWebViewController controller, WebUri? url) async {
        debugPrint('WebView Loading Started: ${url?.toString() ?? "Unknown URL"}');
        _cancelStabilityTimer();
        if (url?.toString().startsWith(loginUrl) == true) {
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
        if (url?.toString().startsWith(loginUrl) == true) {
          await _injectLoginCss();
        }

        if (pageUrl.startsWith("https://www.furaffinity.net/") ||
            pageUrl == "https://www.furaffinity.net") {
          final cookies = await CookieManager.instance().getCookies(
            url: WebUri("https://www.furaffinity.net"),
          );

          final aCookie = cookies.firstWhereOrNull((c) => c.name == 'a');
          if (aCookie != null && aCookie.value.isNotEmpty) {
            for (var c in cookies) {
              await _secureStorage.write(
                  key: 'fa_cookie_${c.name}', value: c.value);
            }

            // Read previous login state BEFORE we set true
            final prefs = await SharedPreferences.getInstance();
            final wasLoggedIn = prefs.getBool('isLoggedIn') ?? false;

            await _saveLoginState(true);
            setState(() => isLoggedIn = true);

            await _setSfwCookieToNSFW();

            _cancelStabilityTimer();

            if (!_profileFetched) {
              _profileFetched = true;
              await _fetchUserProfile();
            }

            if (!wasLoggedIn && !_loginSnackShownThisRun && mounted) {
              _loginSnackShownThisRun = true;
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Logged in successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
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
        const String passwordRecoveryPath = '/lostpw/';
        if (uri != null &&
            uri.host.contains('furaffinity.net') &&
            uri.path.contains(passwordRecoveryPath)) {
          debugPrint("Password recovery URL detected.");
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            debugPrint('Opened Password Recovery in external browser.');
            return NavigationActionPolicy.CANCEL;
          } else {
            debugPrint('Could not launch $uri');
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

  void _startElementStabilityCheck() {
    _cancelStabilityTimer();
    _elementCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
          if (_webViewController == null) return;

          String? html = await _webViewController!
              .evaluateJavascript(source: "document.documentElement.outerHTML;");

          bool isClassicTheme =
              html != null && html.contains('data-static-path=\"/themes/classic\"');

          bool usernameElementFound = isClassicTheme &&
              RegExp(r'<(?:a|span) id="my-username"').hasMatch(html);

          bool avatarElementFound =
              !isClassicTheme && html != null && html.contains('loggedin_user_avatar');

          bool elementFound = usernameElementFound || avatarElementFound;

          if (elementFound) {
            if (_firstTimeElementFound == null) {
              _firstTimeElementFound = DateTime.now();
            } else {
              final elapsed =
              DateTime.now().difference(_firstTimeElementFound!);
              if (elapsed >= const Duration(seconds: 1)) {
                setState(() {
                  _mainPageStable = true;
                  isLoggedIn = true;
                });
                _cancelStabilityTimer();

                final cookies = await CookieManager.instance().getCookies(
                  url: WebUri("https://www.furaffinity.net"),
                );
                for (var c in cookies) {
                  await _secureStorage.write(
                      key: 'fa_cookie_${c.name}', value: c.value);
                }

                final prefs = await SharedPreferences.getInstance();
                final wasLoggedIn = prefs.getBool('isLoggedIn') ?? false;

                await _saveLoginState(true);
                await _setSfwCookieToNSFW();

                if (!_profileFetched) {
                  _profileFetched = true;
                  await _fetchUserProfile();
                }

                if (!wasLoggedIn && !_loginSnackShownThisRun && mounted) {
                  _loginSnackShownThisRun = true;
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logged in successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
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

  Widget _buildMainAppScreen(BuildContext context) {
    if (isLoadingProfile || _userProfile == null) {
      return const Center(
          child: PulsatingLoadingIndicator(
              size: 108.0, assetPath: 'assets/icons/fathemed.png'));
    }
    return DrawerUserController(
      key: _drawerKey,
      screenIndex: drawerIndex,
      drawerWidth: MediaQuery.of(context).size.width * 0.75,
      onDrawerCall: (DrawerIndex drawerIndexdata) {
        _changeIndex(drawerIndexdata);
      },
      screenView: _buildSelectedScreen(),
      onLogout: _logout,
      userProfile: _userProfile!,
      onNoteCounterTap: _onNoteCounterTap,
      onNotesCountChanged: (int count) {
        setState(() {
          _unreadCount = count;
        });
      },
      onNotificationsUpdated: _onNotificationsUpdated,
      onBadgeTap: openNotificationsWithSection,
      enableSwipe: _selectedIndex != 9,
    );
  }

  Future<void> _setCookiesFromPrefs() async {
    List<String> cookieKeys = ['a', 'b', 'cc', 'folder', 'nodesc', 'sz', 'sfw'];
    for (var key in cookieKeys) {
      String storageKey = 'fa_cookie_$key';
      String? cookieValue = await _secureStorage.read(key: storageKey);
      if (cookieValue != null && cookieValue.isNotEmpty) {
        await CookieManager.instance().setCookie(
          url: WebUri('https://www.furaffinity.net'),
          name: key,
          value: cookieValue,
          domain: '.furaffinity.net',
          path: '/',
          isHttpOnly: true,
          isSecure: true,
          expiresDate:
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
        );
      }
    }
  }

  Widget _buildSelectedScreen() {
    bool shouldForceRefresh = _forceNotesRefresh;
    if (_forceNotesRefresh && _selectedIndex == 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _forceNotesRefresh = false;
          });
        }
      });
    }
    return IndexedStack(
      index: _selectedIndex,
      children: [
        // 0: Browse
        Scaffold(
          appBar: AppBar(
            title: const Text('Browse'),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () async {
                    final updatedFilters = await Navigator.push<Map<String, String>>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FiltersScreen(selectedFilters: browseFilters),
                      ),
                    );
                    if (updatedFilters != null) {
                      setState(() => browseFilters = updatedFilters);
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
        // 1: Search
        SearchScreen(
          key: _searchKey,
          searchFilters: searchFilters,
          onFilterUpdated: (updatedSearchFilters) {
            setState(() {
              searchFilters = updatedSearchFilters;
            });
          },
        ),
        // 2: Submissions
        SubmissionsScreen(key: _submissionsKey),
        // 3: Notifications
        NotificationsScreen(
          drawerKey: _drawerKey,
          key: ValueKey(_notificationsInitialSection),
          initialSection: _notificationsInitialSection,
        ),
        // 4: Notes
        NotesScreen(
          drawerKey: _drawerKey,
          forceRefresh: shouldForceRefresh,
          key: _notesKey,
        ),
      ],
    );
  }

  void _changeIndex(DrawerIndex indexScreen) {
    if (indexScreen == DrawerIndex.Upload) {
      setState(() {
        drawerIndex = indexScreen;
      });
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => const UploadSubmissionScreen()),
      ).then((_) {
        if (!mounted) return;
        setState(() {
          drawerIndex = DrawerIndex.HOME;
          _selectedIndex = 0;
        });
      });
    } else {
      setState(() {
        drawerIndex = indexScreen;
        switch (indexScreen) {
          case DrawerIndex.HOME:
            _selectedIndex = 0;
            break;
          case DrawerIndex.Submissions:
            _selectedIndex = 2;
            _submissionsKey.currentState?.refreshSubmissionsManually();
            break;
          case DrawerIndex.Notes:
            _selectedIndex = 4;
            break;
          case DrawerIndex.Notifications:
            _selectedIndex = 3;
            break;
          default:
            debugPrint("Unhandled DrawerIndex: $indexScreen");
            _selectedIndex = 0;
            break;
        }
      });
      if (drawerIndex != DrawerIndex.HOME) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            drawerIndex = DrawerIndex.HOME;
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
      await CookieManager.instance().deleteAllCookies();
      debugPrint('[Logout] All cookies deleted.');

      await _secureStorage.deleteAll();
      debugPrint('[Logout] FlutterSecureStorage cleared.');

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      await DefaultCacheManager().emptyCache();
      debugPrint('[Logout] Image cache cleared.');

      final faNotificationService =
      Provider.of<FANotificationService>(context, listen: false);
      faNotificationService.clearAllNotifications();

      setState(() {
        isLoggedIn = false;
        _userProfile = null;
        _unreadCount = 0;
        _currentNotifications = null;
        isLoadingProfile = false;
        drawerIndex = DrawerIndex.HOME;
        _selectedIndex = 0;
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
      Navigator.of(context).pop();
      debugPrint('[Logout] Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during logout: $e')),
      );
    }
  }

  Future<void> _injectLoginCss() async {
    await _webViewController?.injectCSSCode(
      source: '''
      /* Minimal CSS to hide some FA elements on login page */
      .mobile-navigation,
      nav#ddmenu,
      .news-block,
      .leaderboardAd,
      .mobile-notification-bar,
      .footerAds,
      .floatleft,
      .submenu-trigger,
      .banner-svg,
      .message-bar-desktop,
      .notification-container,
      .dropdown,
      #main-window > nav,
      #main-window > .message-bar-desktop,
      #main-window > .news-block,
      #footer .auto_link.footer-links,
      #footer .footerAds__slot,
      #footer .footerAds__column {
        display: none !important;
      }

      /* Center username, password, and login button */
      section.login-page .section-body {
        text-align: center !important;
      }

      section.login-page .section-body input[type="text"],
      section.login-page .section-body input[type="password"],
      section.login-page .section-body input[type="submit"] {
        display: block !important;
        margin: 0 auto !important;
        margin-bottom: 10px !important;
        max-width: 300px;
      }
    ''',
    );
  }

  Future<void> _setSfwCookieToNSFW() async {
    await _secureStorage.write(key: 'fa_cookie_sfw', value: '0');
    await CookieManager.instance().setCookie(
      url: WebUri('https://www.furaffinity.net'),
      name: 'sfw',
      value: '0',
      domain: '.furaffinity.net',
      path: '/',
      isHttpOnly: true,
      isSecure: true,
      expiresDate:
      DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<NotificationSettingsProvider, FANotificationService>(
      builder: (context, settings, faNotificationService, child) {
        return Scaffold(
          body: isLoggedIn ? _buildMainAppScreen(context) : _buildWebView(),
          bottomNavigationBar: Column(
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
                      icon: Image.asset(
                        'assets/icons/submissions.png',
                        width: 27,
                        height: 27,
                        color: Colors.grey,
                      ),
                      activeIcon: Image.asset(
                        'assets/icons/submissions.png',
                        width: 27,
                        height: 27,
                        color: const Color(0xFFE09321),
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
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        showBadge:
                        _getNotificationsEnabledSum(settings, faNotificationService) >
                            0,
                        child: const Icon(Icons.notifications),
                        position: badges.BadgePosition.topEnd(top: -5, end: -7),
                        padding: const EdgeInsets.all(2),
                        badgeColor: Colors.red,
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
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        showBadge: _unreadCount > 0,
                        child: const Icon(Icons.mail),
                        position: badges.BadgePosition.topEnd(top: -5, end: -7),
                        padding: const EdgeInsets.all(2),
                        badgeColor: Colors.red,
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
        );
      },
    );
  }
}
