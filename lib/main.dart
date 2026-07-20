import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'package:fanotifier/shared/theme/app_theme.dart';
import 'package:fanotifier/app/bootstrap/app_bootstrap.dart';
import 'package:fanotifier/app/composition/app_providers.dart';
import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:fanotifier/app/navigation/app_notification_navigation.dart';
import 'package:fanotifier/core/preferences/app_foreground_state_preference.dart';
import 'package:fanotifier/features/drawer/data/app_update_service.dart';
import 'package:fanotifier/features/drawer/presentation/drawer_user_controller.dart';
import 'package:fanotifier/features/drawer/presentation/update_screen.dart';
import 'package:fanotifier/features/home/presentation/home_screen.dart';
import 'package:fanotifier/features/notifications/data/notification_badge_state.dart'
    as notification_badge;
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';

import 'core/logging/app_logging.dart';

final GlobalKey<DrawerUserControllerState> drawerKey =
    GlobalKey<DrawerUserControllerState>();

const bool _forceShowUpdateScreen = false;

const AppForegroundStatePreference _appForegroundStatePreference =
    AppForegroundStatePreference();

@pragma('vm:entry-point')
void callbackDispatcher() {
  configureBackgroundWorkmanager(callbackDispatcher);
  runBackgroundNotificationWorker();
}

void main() async {
  await initializeAppInfrastructure(
    callbackDispatcher: callbackDispatcher,
  );
  debugPrint("===============================================");
  debugPrint("APP STARTING: ${DateTime.now()}");
  debugPrint("===============================================");
  final timezoneProvider = AppProviders.createTimezoneProvider();
  runApp(
    AppProviders(
      timezoneProvider: timezoneProvider,
      child: const MyApp(),
    ),
  );
  final t0 = DateTime.now();
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    debugPrint(
        '[BOOT] First frame at ${DateTime.now()} (+${DateTime.now().difference(t0)})');
    await afterFirstFrameBoot(timezoneProvider);
  });
  Future.delayed(const Duration(seconds: 3), () {
    debugPrint(
        '[BOOT][WATCHDOG] If no first-frame log appeared, splash is still gating.');
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSub;
  Timer? _activeHeartbeatTimer;
  bool _updateScreenOpened = false;
  bool _isLifecycleResumed = false;
  bool _desiredAppActive = false;
  Future<void> _appStateWriteQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
    _isLifecycleResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_isLifecycleResumed) {
      _setAppActive(true);
      _startActiveHeartbeat();
    }
    _checkForUpdateOnAppStart();
  }

  Future<void> _checkForUpdateOnAppStart() async {
    final updateInfo = await fetchLatestAppUpdateInfo();
    if (!mounted ||
        (updateInfo == null && !_forceShowUpdateScreen) ||
        (!_forceShowUpdateScreen &&
            !updateInfo!.updateAvailable &&
            updateInfo.currentVersionAllowed) ||
        _updateScreenOpened) {
      return;
    }

    final canDismiss =
        _forceShowUpdateScreen || updateInfo?.currentVersionAllowed == true;
    _updateScreenOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => UpdateScreen(
            canDismiss: canDismiss,
          ),
          fullscreenDialog: true,
        ),
      );
    });
  }

  void _startActiveHeartbeat() {
    _activeHeartbeatTimer?.cancel();
    _activeHeartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_isLifecycleResumed) {
        _setAppActive(true, resetBadge: false);
      }
    });
  }

  void _stopActiveHeartbeat() {
    _activeHeartbeatTimer?.cancel();
    _activeHeartbeatTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appLog('===============================================');
    appLog('APP LIFECYCLE CHANGED: $state');
    appLog('Time: ${DateTime.now()}');
    appLog('===============================================');
    switch (state) {
      case AppLifecycleState.resumed:
        _isLifecycleResumed = true;
        _setAppActive(true);
        _startActiveHeartbeat();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await appNotificationNavigation.processPending(
            from: 'app_lifecycle_resumed',
          );
        });
        appLog('→ App RESUMED - Background fetch DISABLED');
        break;
      case AppLifecycleState.inactive:
        appLog('→ App INACTIVE (transitional state)');
        break;
      case AppLifecycleState.paused:
        _isLifecycleResumed = false;
        _stopActiveHeartbeat();
        _setAppActive(false);
        appLog('→ App PAUSED - Background fetch ENABLED');
        break;
      case AppLifecycleState.detached:
        _isLifecycleResumed = false;
        _stopActiveHeartbeat();
        _setAppActive(false);
        appLog('→ App DETACHED - Background fetch ENABLED');
        break;
      case AppLifecycleState.hidden:
        _isLifecycleResumed = false;
        _stopActiveHeartbeat();
        _setAppActive(false);
        appLog('→ App HIDDEN - Background fetch ENABLED');
        break;
    }
  }

  @override
  void dispose() {
    _isLifecycleResumed = false;
    _stopActiveHeartbeat();
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    _setAppActive(false);
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _linkSub = _appLinks!.uriLinkStream.listen((Uri uri) {
      if (navigatorKey.currentContext != null) {
        handleFALink(navigatorKey.currentContext!, uri.toString());
      }
    }, onError: (_) {});
  }

  Future<void> _setAppActive(bool active, {bool resetBadge = true}) {
    _desiredAppActive = active;
    final shouldResetBadge = active && resetBadge;
    _appStateWriteQueue = _appStateWriteQueue.catchError((_) {}).then((_) async {
      final stateToPersist = _desiredAppActive;
      try {
        await _appForegroundStatePreference
            .persistAppForegroundState(stateToPersist);
        appLog(
            "[APP STATE] Set to: ${stateToPersist ? 'ACTIVE' : 'INACTIVE'}");
        if (stateToPersist && shouldResetBadge && _desiredAppActive) {
          await notification_badge.resetBadgeCounter();
          await adaptiveBackgroundFetchScheduler
              .resetAdaptiveBackgroundFetch();
        }
      } catch (e) {
        appLog("[ERROR] Failed to set app state: $e");
      }
    });
    return _appStateWriteQueue;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: rootMessengerKey,
      title: 'FA Notifier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      home: Builder(
        builder: (context) {
          final mediaQuery = MediaQuery.of(context);
          final homeMediaQuery = mediaQuery.copyWith(
            // Keep home/tabs insensitive to keyboard bottom insets from pushed routes.
            viewInsets: mediaQuery.viewInsets.copyWith(bottom: 0),
            padding: mediaQuery.padding.copyWith(
              bottom: mediaQuery.viewPadding.bottom,
            ),
          );
          return MediaQuery(
            data: homeMediaQuery,
            child: const HomeScreen(),
          );
        },
      ),
    );
  }
}
