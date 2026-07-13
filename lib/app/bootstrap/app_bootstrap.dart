import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'package:FANotifier/app/analytics_privacy.dart';
import 'package:FANotifier/app/navigation/app_notification_navigation.dart';
import 'package:FANotifier/core/cache/CacheMonitorService.dart';
import 'package:FANotifier/core/cache/custom_cache_manager.dart';
import 'package:FANotifier/core/logging/app_logging.dart';
import 'package:FANotifier/core/network/fresh_http_overrides.dart';
import 'package:FANotifier/core/timezone/presentation/timezone_provider.dart';
import 'package:FANotifier/features/notifications/data/adaptive_background_fetch_scheduler.dart'
    as background_scheduler;
import 'package:FANotifier/app/background/background_notification_worker.dart';
import 'package:FANotifier/features/notifications/data/background_workmanager_initializer.dart';
import 'package:FANotifier/features/notifications/data/notification_service.dart';
import 'package:FANotifier/core/network/fa_http.dart';

late final BackgroundWorkmanagerInitializer backgroundWorkmanagerInitializer;
late final background_scheduler.AdaptiveBackgroundFetchScheduler
    adaptiveBackgroundFetchScheduler;
bool _backgroundWorkmanagerConfigured = false;

void configureBackgroundWorkmanager(void Function() callbackDispatcher) {
  if (_backgroundWorkmanagerConfigured) return;
  backgroundWorkmanagerInitializer =
      BackgroundWorkmanagerInitializer(callbackDispatcher: callbackDispatcher);
  adaptiveBackgroundFetchScheduler =
      background_scheduler.AdaptiveBackgroundFetchScheduler(
    workmanagerInitializer: backgroundWorkmanagerInitializer,
  );
  _backgroundWorkmanagerConfigured = true;
}

void runBackgroundNotificationWorker() {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppLogging();
  final worker = BackgroundNotificationWorker(
    adaptiveBackgroundFetchScheduler: adaptiveBackgroundFetchScheduler,
  );
  Workmanager().executeTask(worker.execute);
}

Future<void> initializeAppInfrastructure({
  required void Function() callbackDispatcher,
}) async {
  configureBackgroundWorkmanager(callbackDispatcher);
  WidgetsFlutterBinding.ensureInitialized();
  configureAppLogging();
  try {
    await NotificationService().init(
      onNotificationTap: appNotificationNavigation.handleTap,
    );
  } catch (error, stackTrace) {
    debugPrint('[BOOT] early notification tap init failed: $error');
    debugPrint(stackTrace.toString());
  }
  await Firebase.initializeApp();
  await setupAnalyticsPrivacy();
  await FAHttp.init();
  AppLifecycleNetworkReset.attach();
  HttpOverrides.global = FreshHttpOverrides();
  try {
    await backgroundWorkmanagerInitializer.ensureWorkmanagerInitialized();
  } catch (error, stackTrace) {
    debugPrint('[BOOT] early Workmanager init failed: $error');
    debugPrint(stackTrace.toString());
  }
}

Future<void> afterFirstFrameBoot(TimezoneProvider timezoneProvider) async {
  try {
    await appNotificationNavigation.processPending(
      from: 'after_first_frame_boot',
    );
    await PackageInfo.fromPlatform();
    tz.initializeTimeZones();
    await timezoneProvider.fetchTimezone();
    final notificationService = NotificationService();
    await notificationService.configurePlatform();
    await notificationService.updateNotificationChannels();
    await _requestAndroidNotificationPermission();
    await _requestIOSNotificationPermission();
    final cacheManager = CustomCacheManager();
    final cacheMonitorService = CacheMonitorService(cacheManager);
    await cacheMonitorService.checkStorageUsage();
    await backgroundWorkmanagerInitializer.ensureWorkmanagerInitialized();
    if (Platform.isAndroid) {
      await adaptiveBackgroundFetchScheduler.applyBackgroundFetchInterval(
        background_scheduler.backgroundFetchFastIntervalMinutes,
      );
      debugPrint('Android background task registered');
    } else if (Platform.isIOS) {
      debugPrint('iOS background task handler registered');
    }
  } catch (error, stackTrace) {
    debugPrint('[BOOT] afterFirstFrame error: $error');
    debugPrint(stackTrace.toString());
  }
}

Future<void> _requestAndroidNotificationPermission() async {
  if (!Platform.isAndroid) return;
  final status = await Permission.notification.status;
  if (status.isDenied || status.isPermanentlyDenied) {
    final newStatus = await Permission.notification.request();
    debugPrint(
      'Android notification permission: ${newStatus.isGranted ? "granted" : "denied"}',
    );
  }
}

Future<void> _requestIOSNotificationPermission() async {
  if (!Platform.isIOS) return;
  final status = await Permission.notification.status;
  if (status.isDenied || status.isPermanentlyDenied) {
    final newStatus = await Permission.notification.request();
    debugPrint(
      'iOS notification permission: ${newStatus.isGranted ? "granted" : "denied"}',
    );
  }
}

class AppLifecycleNetworkReset with WidgetsBindingObserver {
  static final AppLifecycleNetworkReset _instance =
      AppLifecycleNetworkReset._();

  AppLifecycleNetworkReset._();

  static void attach() {
    WidgetsBinding.instance.addObserver(_instance);
  }

  static void detach() {
    WidgetsBinding.instance.removeObserver(_instance);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FAHttp.reset();
    }
  }
}
