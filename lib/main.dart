import 'dart:io';
import 'dart:convert';
import 'package:FANotifier/providers/NotificationNavigationProvider.dart';
import 'package:FANotifier/providers/timezone_provider.dart';
import 'package:FANotifier/screens/message_model.dart';
import 'package:FANotifier/services/CacheMonitorService.dart';
import 'package:FANotifier/services/fa_cookie_helper.dart';
import 'package:FANotifier/services/fa_http.dart';
import 'package:FANotifier/services/fa_notification_service.dart';
import 'package:FANotifier/services/pending_navigation.dart';
import 'package:FANotifier/utils/notes_notifications_text_edit.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_app_badge_control/flutter_app_badge_control.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'analytics_privacy.dart';
import 'custom_cache_manager.dart';
import 'custom_drawer/drawer_user_controller.dart';
import 'model/notifications.dart';
import 'services/activities_notification_state.dart';
import 'services/notification_service.dart';
import 'utils.dart';
import 'utils/message_storage.dart';
import 'home_screen.dart';
import 'app_theme.dart';
import 'providers/notification_settings_provider.dart';
import 'providers/thumbnail_display_settings_provider.dart';
import 'services/fa_service.dart';
import 'package:provider/provider.dart';
import 'utils/notification_counts.dart';
import 'package:html/dom.dart' as dom;
import 'utils/fa_link_handler.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';


class FreshHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.idleTimeout = const Duration(seconds: 10);
    client.connectionTimeout = const Duration(seconds: 20);
    client.autoUncompress = true;
    client.maxConnectionsPerHost = 8;
    client.userAgent = FAHttp.userAgent;
    return client;
  }
}


final RouteObserver<ModalRoute<dynamic>> routeObserver = RouteObserver<ModalRoute<dynamic>>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<DrawerUserControllerState> drawerKey = GlobalKey<DrawerUserControllerState>();

const String fetchBackgroundTask = "fetchBackgroundTask";
const String iOSWorkInitTask = "com.blazesmoker.FANotifier.refresh";

@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    debugPrint("===============================================");
    debugPrint("BACKGROUND TASK TRIGGERED: $task");
    debugPrint("Time: ${DateTime.now()}");
    debugPrint("Input data: $inputData");
    debugPrint("===============================================");
    final startTime = DateTime.now();
    try {
      final notificationService = NotificationService();
      await notificationService.init();
      debugPrint("[BG] NotificationService initialized");
      SharedPreferences prefs;
      try {
        prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        debugPrint('[BG] SharedPreferences loaded successfully');
        await FAHttp.initFromPrefs(prefs: prefs);
        HttpOverrides.global = FreshHttpOverrides();
      } catch (e) {
        debugPrint('[BG ERROR] Failed to load SharedPreferences: $e');
        return Future.value(false);
      }
      bool isAppActive = prefs.getBool("isAppActive") ?? false;
      debugPrint('[BG] App active status: $isAppActive');
      if (isAppActive) {
        debugPrint('[BG] App is ACTIVE - skipping background fetch');
        debugPrint('[BG] Task completed (skipped) in ${DateTime.now().difference(startTime).inSeconds}s');
        return Future.value(true);
      }
      debugPrint('[BG] App is INACTIVE - proceeding with background fetch');
      if (task == fetchBackgroundTask || task == iOSWorkInitTask) {
        debugPrint('[BG] Valid background task detected: $task');
        try {
          bool didFirstRunSkip = prefs.getBool('did_first_run_skip') ?? false;
          debugPrint('[BG] First run skip status: $didFirstRunSkip');
          if (!didFirstRunSkip) {
            debugPrint('[BG] First run not complete - skipping notifications');
            return Future.value(true);
          }
          debugPrint('[BG] === Starting UNREAD NOTES CHECK ===');
          try {
            final List<Message> fetchedInbox = await _fetchInboxTwoPagesBg();
            debugPrint('[BG] Fetched ${fetchedInbox.length} messages from inbox');
            final Set<String> shownSet = await MessageStorage.getShownNoteIds();
            debugPrint('[BG] Already shown: ${shownSet.length} message IDs');
            final List<Message> unread = fetchedInbox.where((m) => m.isUnread).toList();
            debugPrint('[BG] Found ${unread.length} unread messages');
            if (unread.isNotEmpty) {
              final List<Message> newNotes = unread.where((m) => !shownSet.contains(m.id)).toList();
              debugPrint('[BG] New unread messages: ${newNotes.length}');
              for (var msg in newNotes) {
                try {
                  debugPrint('[BG] Processing message: ${msg.id} from ${msg.sender}');
                  final String content = await _fetchMessageContentInBackground(msg.link);
                  final String payload = 'note_${msg.id}';
                  await notificationService.showNotification(
                    msg.id.hashCode,
                    'New Note from ${msg.sender}',
                    content,
                    payload,
                    'notes',
                  );
                  debugPrint('[BG] Notification shown for message ${msg.id}');
                  if (Platform.isIOS) {
                    int currentBadge = await getBadgeCounter();
                    int newBadge = currentBadge + 1;
                    await updateBadgeCounter(newBadge);
                    debugPrint('[BG] Badge updated to: $newBadge');
                  }
                  await _markAsUnreadBackground(msg);
                  debugPrint('[BG] Message ${msg.id} marked as unread on server');
                } catch (e) {
                  debugPrint('[BG ERROR] Failed to process message ${msg.id}: $e');
                }
              }
              if (newNotes.isNotEmpty) {
                final List<String> newIds = newNotes.map((m) => m.id).toList();
                await MessageStorage.addShownNoteIds(newIds);
                debugPrint('[BG] Saved ${newIds.length} new message IDs');
              }
            }
          } catch (e) {
            debugPrint('[BG ERROR] Notes check failed: $e');
          }
          debugPrint('[BG] === Starting NOTIFICATION COUNTS CHECK ===');
          try {
            final faService = FaService();
            final Notifications? newNotifications = await faService.fetchNotifications();
            if (newNotifications != null) {
              final NotificationCounts newCounts = NotificationCounts(
                submissions: int.tryParse(newNotifications.submissions) ?? 0,
                watches: int.tryParse(newNotifications.watches) ?? 0,
                comments: int.tryParse(newNotifications.comments) ?? 0,
                favorites: int.tryParse(newNotifications.favorites) ?? 0,
                journals: int.tryParse(newNotifications.journals) ?? 0,
                notes: int.tryParse(newNotifications.notes) ?? 0,
              );
              debugPrint('[BG] New counts: S:${newCounts.submissions} W:${newCounts.watches} C:${newCounts.comments} F:${newCounts.favorites} J:${newCounts.journals} N:${newCounts.notes}');
              final bool submissionsEnabled = prefs.getBool('drawer_notif_submissions_enabled') ?? true;
              final bool watchesEnabled = prefs.getBool('drawer_notif_watches_enabled') ?? true;
              final bool commentsEnabled = prefs.getBool('drawer_notif_comments_enabled') ?? true;
              final bool favoritesEnabled = prefs.getBool('drawer_notif_favorites_enabled') ?? true;
              final bool journalsEnabled = prefs.getBool('drawer_notif_journals_enabled') ?? true;
              final bool notesEnabled = prefs.getBool('drawer_notif_notes_enabled') ?? true;

              final ActivitiesDiff diff = await ActivitiesNotificationStateStore()
                  .diffAndUpdateLastSeen(currentCounts: newCounts);
              debugPrint(
                  '[BG] Last-seen counts: S:${diff.previous.submissions} W:${diff.previous.watches} C:${diff.previous.comments} F:${diff.previous.favorites} J:${diff.previous.journals} N:${diff.previous.notes}');
              debugPrint(
                  '[BG] Increased by:     S:${diff.increasedBy.submissions} W:${diff.increasedBy.watches} C:${diff.increasedBy.comments} F:${diff.increasedBy.favorites} J:${diff.increasedBy.journals} N:${diff.increasedBy.notes}');

              // Notify based on per-category increases, but only for enabled categories.
              final NotificationCounts enabledIncreases = NotificationCounts(
                submissions: submissionsEnabled ? diff.increasedBy.submissions : 0,
                watches: watchesEnabled ? diff.increasedBy.watches : 0,
                comments: commentsEnabled ? diff.increasedBy.comments : 0,
                favorites: favoritesEnabled ? diff.increasedBy.favorites : 0,
                journals: journalsEnabled ? diff.increasedBy.journals : 0,
                notes: notesEnabled ? diff.increasedBy.notes : 0,
              );

              final bool shouldNotify = enabledIncreases.submissions > 0 ||
                  enabledIncreases.watches > 0 ||
                  enabledIncreases.comments > 0 ||
                  enabledIncreases.favorites > 0 ||
                  enabledIncreases.journals > 0 ||
                  enabledIncreases.notes > 0;


              final NotificationCounts filteredCounts = NotificationCounts(
                submissions: submissionsEnabled ? newCounts.submissions : 0,
                watches: watchesEnabled ? newCounts.watches : 0,
                comments: commentsEnabled ? newCounts.comments : 0,
                favorites: favoritesEnabled ? newCounts.favorites : 0,
                journals: journalsEnabled ? newCounts.journals : 0,
                notes: notesEnabled ? newCounts.notes : 0,
              );
              final String messageBody = _buildNotificationMessage(filteredCounts);

              // Only show a system notification on an increase.
              if (shouldNotify) {
                final bool soundActivitiesEnabled =
                    prefs.getBool('sound_new_activities_enabled') ?? true;
                final bool vibrationActivitiesEnabled =
                    prefs.getBool('vibration_new_activities_enabled') ?? true;
                if (soundActivitiesEnabled || vibrationActivitiesEnabled) {
                  await notificationService.showNotification(
                    999999,
                    'New FA Activity',
                    messageBody,
                    'activity_fa_activity',
                    'activities',
                  );
                  debugPrint('[BG] Activity notification shown: $messageBody');
                } else {
                  debugPrint(
                      '[BG] Activities sound+vibration disabled; not showing notification.');
                }
              } else {
                debugPrint('[BG] No enabled category increased; not notifying.');
              }
            } else {
              debugPrint('[BG] No notification data received from FA');
            }
          } catch (e) {
            debugPrint('[BG ERROR] Notification counts check failed: $e');
          }
          debugPrint('[BG] === Task completed successfully ===');
          debugPrint('[BG] Total duration: ${DateTime.now().difference(startTime).inSeconds}s');
          return Future.value(true);
        } catch (e, stackTrace) {
          debugPrint('[BG ERROR] Task failed: $e');
          debugPrint('[BG ERROR] Stack: $stackTrace');
          if (e.toString().contains('network') ||
              e.toString().contains('timeout') ||
              e.toString().contains('connection') ||
              e.toString().contains('SocketException')) {
            debugPrint('[BG] Network error detected - will retry');
            return Future.value(false);
          }
          debugPrint('[BG] Non-network error - marking as complete');
          return Future.value(true);
        }
      }
      debugPrint('[BG] Unknown task type: $task');
      return Future.value(true);
    } catch (e) {
      debugPrint('[BG FATAL ERROR] Callback dispatcher crash: $e');
      return Future.value(false);
    }
  });
}

String _buildNotificationMessage(NotificationCounts counts) {
  final parts = <String>[];
  if (counts.submissions > 0) parts.add('${counts.submissions}S');
  if (counts.watches > 0) parts.add('${counts.watches}W');
  if (counts.comments > 0) parts.add('${counts.comments}C');
  if (counts.favorites > 0) parts.add('${counts.favorites}F');
  if (counts.journals > 0) parts.add('${counts.journals}J');
  if (counts.notes > 0) parts.add('${counts.notes}N');
  return parts.join(' | ');
}

Future<void> debugLogs(String message) async {
  final timestamp = DateTime.now().toIso8601String();
  debugPrint('[$timestamp] $message');
}

Future<int> getBadgeCounter() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('badgeCounter') ?? 0;
}

Future<void> updateBadgeCounter(int newCount) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('badgeCounter', newCount);
  if (Platform.isIOS) {
    FlutterAppBadgeControl.updateBadgeCount(newCount);
  }
}

Future<void> resetBadgeCounter() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('badgeCounter', 0);
  if (Platform.isIOS) {
    FlutterAppBadgeControl.removeBadge();
  }
}

Future<List<Message>> _fetchInboxTwoPagesBg() async {
  final storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  final cookieA = await storage.read(key: 'fa_cookie_a');
  final cookieB = await storage.read(key: 'fa_cookie_b');
  if (cookieA == null || cookieB == null) {
    debugPrint('[BG] No cookies found - user not logged in');
    throw Exception('Not logged in');
  }
  final result = <Message>[];
  for (int page = 1; page <= 2; page++) {
    final url = Uri.parse('https://www.furaffinity.net/msg/pms/$page/');
    final resp = await http.get(
      url,
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB; folder=inbox',
        ),
        'User-Agent': FAHttp.userAgent,
      },
    );
    if (resp.statusCode == 200) {
      final decoded = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final doc = html_parser.parse(decoded);
      var noteElements = doc.querySelectorAll('.message-center-pms-note-list-view .note-list-container');
      if (noteElements.isEmpty) {
        noteElements = doc.querySelectorAll('#notes-list .note-list-container');
      }
      if (noteElements.isEmpty) {
        final bool isClassic = doc.querySelector('body[data-static-path="/themes/classic"]') != null;
        if (isClassic) {
          List<dom.Element> classicRows = List.from(doc.querySelectorAll('#notes-list tr.note'));
          if (classicRows.isNotEmpty && classicRows.last.querySelector('input[type="checkbox"]') == null) {
            classicRows.removeLast();
          }
          noteElements = classicRows;
        } else {
          noteElements = doc.querySelectorAll('td.note-list-container tr.note');
        }
      }
      if (noteElements.isEmpty) break;
      for (var noteEl in noteElements) {
        final subject = noteEl.querySelector('a.notelink')?.text.trim() ?? 'No subject';
        final sender = noteEl.querySelector('.c-usernameBlock__displayName .js-displayName')?.text.trim() ?? 'Unknown sender';
        final checkbox = noteEl.querySelector('input[type="checkbox"]');
        final id = checkbox?.attributes['value'] ?? '';
        final aTag = noteEl.querySelector('a.notelink');
        String link = '';
        if (aTag != null) {
          final classicLink = aTag.attributes['href'] ?? '';
          if (classicLink.startsWith('/viewmessage/')) {
            link = classicLink;
          } else {
            link = aTag.attributes['newhref'] ?? classicLink;
          }
        }
        final date = noteEl.querySelector('span.popup_date')?.attributes['title'] ?? 'Unknown date';
        final isUnread = noteEl.querySelector('img.unread') != null;
        result.add(Message(
          id: id,
          subject: subject,
          sender: sender,
          recipient: '',
          date: date,
          link: link,
          isUnread: isUnread,
        ));
      }
    } else {
      throw Exception('HTTP ${resp.statusCode}');
    }
  }
  return result;
}

Future<String> _fetchMessageContentInBackground(String link) async {
  final storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  final cookieA = await storage.read(key: 'fa_cookie_a');
  final cookieB = await storage.read(key: 'fa_cookie_b');
  if (cookieA == null || cookieB == null) {
    throw Exception('Not logged in');
  }
  final dio = Dio();
  final cookieJar = CookieJar();
  dio.interceptors.add(CookieManager(cookieJar));
  cookieJar.saveFromResponse(
    Uri.parse('https://www.furaffinity.net'),
    await FaCookieHelper.addCfClearanceCookie(
      [Cookie('a', cookieA), Cookie('b', cookieB)],
    ),
  );
  final resp = await dio.get(
    'https://www.furaffinity.net$link',
    options: Options(
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': FAHttp.userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
      validateStatus: (status) => status != null && status >= 200 && status < 400,
    ),
  );
  if (resp.statusCode == 200) {
    final doc = html_parser.parse(resp.data);
    final modernContentElement = doc.querySelector('.section-body .user-submitted-links');
    if (modernContentElement != null) {
      modernContentElement.querySelectorAll('.noteWarningMessage.noteWarningMessage--scam').forEach((e) => e.remove());
      modernContentElement.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
        final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
        if (fullLink != null) {
          anchor.innerHtml = fullLink;
        }
      });
      final rawHtml = modernContentElement.innerHtml;
      final innerDoc = html_parser.parse(rawHtml);
      final updatedText = innerDoc.body?.text.trim() ?? '';
      final newestContent = extractNewestContent(updatedText);
      return newestContent.isNotEmpty ? newestContent : 'No content';
    }
    final classicContentElement = doc.querySelector('td.noteContent.alt1');
    if (classicContentElement != null) {
      classicContentElement.querySelectorAll('.noteWarningMessage.noteWarningMessage--scam').forEach((e) => e.remove());
      classicContentElement.querySelector('span[style*="color: #999999"]')?.remove();
      classicContentElement.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
        final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
        if (fullLink != null) {
          anchor.innerHtml = fullLink;
        }
      });
      final rawHtml = classicContentElement.innerHtml;
      final innerDoc = html_parser.parse(rawHtml);
      final updatedText = innerDoc.body?.text.trim() ?? '';
      final newestContent = extractNewestContent(updatedText);
      return newestContent.isNotEmpty ? newestContent : 'No content';
    }
    return 'No content';
  } else {
    throw Exception('HTTP ${resp.statusCode}');
  }
}

Future<void> _markAsUnreadBackground(Message msg) async {
  final storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
        accountName: 'flutter_secure_storage_service',
        accessibility: KeychainAccessibility.first_unlock),
  );
  final cookieA = await storage.read(key: 'fa_cookie_a');
  final cookieB = await storage.read(key: 'fa_cookie_b');
  if (cookieA == null || cookieB == null) {
    throw Exception('Not logged in');
  }
  final dio = Dio();
  final cookieJar = CookieJar();
  dio.interceptors.add(CookieManager(cookieJar));
  cookieJar.saveFromResponse(
    Uri.parse('https://www.furaffinity.net'),
    await FaCookieHelper.addCfClearanceCookie(
      [Cookie('a', cookieA), Cookie('b', cookieB)],
    ),
  );
  int pNum = extractPageNumber(msg.link);
  String mId = extractMessageId(msg.link);
  if (mId.isEmpty) {
    final classicMatch = RegExp(r'/viewmessage/(\d+)/').firstMatch(msg.link);
    if (classicMatch != null) {
      mId = classicMatch.group(1)!;
      pNum = 1;
    } else {
      throw Exception('Invalid message ID');
    }
  }
  final formData = {
    'manage_notes': '1',
    'items[]': mId,
    'move_to': 'unread',
  };
  await dio.post(
    'https://www.furaffinity.net/msg/pms/$pNum/$mId/',
    data: formData,
    options: Options(
      headers: {
        'User-Agent': FAHttp.userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': 'https://www.furaffinity.net/msg/pms/$pNum/$mId/',
        'Origin': 'https://www.furaffinity.net',
      },
      followRedirects: false,
      validateStatus: (s) => s != null && (s == 302 || (s >= 200 && s < 300)),
    ),
  );
}

Future<void> requestAndroidNotificationPermission() async {
  if (Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      final newStatus = await Permission.notification.request();
      debugPrint('Android notification permission: ${newStatus.isGranted ? "granted" : "denied"}');
    }
  }
}

Future<void> requestIOSNotificationPermission() async {
  if (Platform.isIOS) {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      final newStatus = await Permission.notification.request();
      debugPrint('iOS notification permission: ${newStatus.isGranted ? "granted" : "denied"}');
    }
  }
}


Future<void> _afterFirstFrameBoot(TimezoneProvider timezoneProvider) async {
  try {
    await PackageInfo.fromPlatform();
    tz.initializeTimeZones();
    await timezoneProvider.fetchTimezone();
    final notificationService = NotificationService();
    await notificationService.init();
    await notificationService.updateNotificationChannels();
    const channel = MethodChannel('app.notifications');
    try {
      await channel.invokeMethod('notifications.ready');
    } catch (_) {}
    await requestAndroidNotificationPermission();
    await requestIOSNotificationPermission();
    final cacheManager = CustomCacheManager();
    final cacheMonitorService = CacheMonitorService(cacheManager);
    await cacheMonitorService.checkStorageUsage();
    debugPrint("Initializing Workmanager...");
    await Workmanager().initialize(callbackDispatcher);
    debugPrint("Workmanager initialized");
    if (Platform.isAndroid) {
      await Workmanager().registerPeriodicTask(
        "FANotify",
        fetchBackgroundTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
      );
      debugPrint("Android background task registered");
    } else if (Platform.isIOS) {
      debugPrint("iOS background task handler registered");
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isAppActive", true);
    debugPrint("App initial state set to ACTIVE");
  } catch (e, st) {
    debugPrint('[BOOT] afterFirstFrame error: $e');
    debugPrint(st as String?);
  }
}

class AppLifecycleNetworkReset with WidgetsBindingObserver {
  static final AppLifecycleNetworkReset _instance = AppLifecycleNetworkReset._();
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await setupAnalyticsPrivacy();
  await FAHttp.init();
  AppLifecycleNetworkReset.attach();
  HttpOverrides.global = FreshHttpOverrides();
  debugPrint("===============================================");
  debugPrint("APP STARTING: ${DateTime.now()}");
  debugPrint("===============================================");
  final timezoneProvider = TimezoneProvider();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TimezoneProvider>.value(value: timezoneProvider),
        ChangeNotifierProvider<NotificationNavigationProvider>(
          create: (_) => NotificationNavigationProvider(),
        ),
        ChangeNotifierProvider<NotificationSettingsProvider>(
          create: (_) => NotificationSettingsProvider(),
        ),
        ChangeNotifierProvider<ThumbnailDisplaySettingsProvider>(
          create: (_) => ThumbnailDisplaySettingsProvider(),
        ),
        ChangeNotifierProvider<FANotificationService>(
          create: (_) => FANotificationService(),
        ),
      ],
      child: const MyApp(),
    ),
  );
  final t0 = DateTime.now();
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    debugPrint('[BOOT] First frame at ${DateTime.now()} (+${DateTime.now().difference(t0)})');
    await _afterFirstFrameBoot(timezoneProvider);
  });
  Future.delayed(const Duration(seconds: 3), () {
    debugPrint('[BOOT][WATCHDOG] If no first-frame log appeared, splash is still gating.');
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
  Timer? _stateDebugTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setAppActive(true);
    _initDeepLinks();
    if (kDebugMode || true) {
      _stateDebugTimer = Timer.periodic(const Duration(minutes: 3), (_) async {
        final prefs = await SharedPreferences.getInstance();
        final isActive = prefs.getBool("isAppActive") ?? false;
        debugPrint("[STATE CHECK] App active: $isActive at ${DateTime.now()}");
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('===============================================');
    debugPrint('APP LIFECYCLE CHANGED: $state');
    debugPrint('Time: ${DateTime.now()}');
    debugPrint('===============================================');
    switch (state) {
      case AppLifecycleState.resumed:
        _setAppActive(true);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await processPendingNavigation(from: 'app_lifecycle_resumed');
        });
        debugPrint('→ App RESUMED - Background fetch DISABLED');
        break;
      case AppLifecycleState.inactive:
        debugPrint('→ App INACTIVE (transitional state)');
        break;
      case AppLifecycleState.paused:
        _setAppActive(false);
        debugPrint('→ App PAUSED - Background fetch ENABLED');
        break;
      case AppLifecycleState.detached:
        _setAppActive(false);
        debugPrint('→ App DETACHED - Background fetch ENABLED');
        break;
      case AppLifecycleState.hidden:
        _setAppActive(false);
        debugPrint('→ App HIDDEN - Background fetch ENABLED');
        break;
    }
  }

  @override
  void dispose() {
    _stateDebugTimer?.cancel();
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

  Future<void> _setAppActive(bool active) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("isAppActive", active);
      await prefs.reload();
      debugPrint("[APP STATE] Set to: ${active ? 'ACTIVE' : 'INACTIVE'}");
      if (active) {
        await resetBadgeCounter();
      }
    } catch (e) {
      debugPrint("[ERROR] Failed to set app state: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: rootMessengerKey,
      title: 'FA Notify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      home: const HomeScreen(),
    );
  }
}

final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();
