import 'dart:io';
import 'dart:convert';
import 'package:FANotifier/providers/NotificationNavigationProvider.dart';
import 'package:FANotifier/providers/timezone_provider.dart';
import 'package:FANotifier/screens/message_model.dart';
import 'package:FANotifier/screens/notifications_provider.dart';
import 'package:FANotifier/services/CacheMonitorService.dart';
import 'package:FANotifier/services/fa_notification_service.dart';
import 'package:FANotifier/utils/notes_notifications_text_edit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_app_badge_control/flutter_app_badge_control.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_local_notifications_platform_interface/src/types.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'custom_cache_manager.dart';
import 'custom_drawer/drawer_user_controller.dart';
import 'model/notifications.dart';
import 'services/notification_service.dart';
import 'utils.dart';
import 'utils/message_storage.dart';
import 'home_screen.dart';
import 'app_theme.dart';
import 'providers/notification_settings_provider.dart';
import 'services/fa_service.dart';
import 'package:provider/provider.dart';
import 'utils/notification_counts.dart';
import 'package:html/dom.dart' as dom;
import 'network.dart';
import 'utils/fa_link_handler.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

final RouteObserver<ModalRoute<dynamic>> routeObserver = RouteObserver<ModalRoute<dynamic>>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<DrawerUserControllerState> drawerKey = GlobalKey<DrawerUserControllerState>();

const String fetchBackgroundTask = "fetchBackgroundTask";
const String iOSWorkInitTask = "com.blazesmoker.FANotifier.refresh";
const String kPreviousSumKey = 'previousSumOfNotifications';

@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().executeTask((task, inputData) async {
    print("===============================================");
    print("BACKGROUND TASK TRIGGERED: $task");
    print("Time: ${DateTime.now()}");
    print("Input data: $inputData");
    print("===============================================");

    final startTime = DateTime.now();

    try {
      // Initialize notification service first
      final notificationService = NotificationService();
      await notificationService.init();
      print("[BG] NotificationService initialized");

      // Get SharedPreferences with reload
      SharedPreferences prefs;
      try {
        prefs = await SharedPreferences.getInstance();
        await prefs.reload(); // Force reload to get latest values
        print('[BG] SharedPreferences loaded successfully');
      } catch (e) {
        print('[BG ERROR] Failed to load SharedPreferences: $e');
        return Future.value(false);
      }

      // Check if app is active
      bool isAppActive = prefs.getBool("isAppActive") ?? false;
      print('[BG] App active status: $isAppActive');

      if (isAppActive) {
        print('[BG] App is ACTIVE - skipping background fetch');
        print('[BG] Task completed (skipped) in ${DateTime.now().difference(startTime).inSeconds}s');
        return Future.value(true);
      }

      print('[BG] App is INACTIVE - proceeding with background fetch');

      // Check if this is a valid background task
      if (task == fetchBackgroundTask || task == iOSWorkInitTask) {

        print('[BG] Valid background task detected: $task');

        try {
          // Check first run status
          bool didFirstRunSkip = prefs.getBool('did_first_run_skip') ?? false;
          print('[BG] First run skip status: $didFirstRunSkip');

          if (!didFirstRunSkip) {
            print('[BG] First run not complete - skipping notifications');
            return Future.value(true);
          }

          // UNREAD NOTES CHECK
          print('[BG] === Starting UNREAD NOTES CHECK ===');

          try {
            final List<Message> fetchedInbox = await _fetchInboxTwoPagesBg();
            print('[BG] Fetched ${fetchedInbox.length} messages from inbox');

            // Get already shown message IDs
            final Set<String> shownSet = await MessageStorage.getShownNoteIds();
            print('[BG] Already shown: ${shownSet.length} message IDs');

            // Filter unread messages
            final List<Message> unread = fetchedInbox.where((m) => m.isUnread).toList();
            print('[BG] Found ${unread.length} unread messages');

            if (unread.isNotEmpty) {
              // Find new unread messages
              final List<Message> newNotes = unread.where((m) => !shownSet.contains(m.id)).toList();
              print('[BG] New unread messages: ${newNotes.length}');

              // Process each new unread message
              for (var msg in newNotes) {
                try {
                  print('[BG] Processing message: ${msg.id} from ${msg.sender}');
                  final String content = await _fetchMessageContentInBackground(msg.link);
                  final String payload = 'note_${msg.id}';

                  // Show notification
                  await notificationService.showNotification(
                    msg.id.hashCode,
                    'New Note from ${msg.sender}',
                    content,
                    payload,
                    'notes',
                  );
                  print('[BG] Notification shown for message ${msg.id}');

                  // Update badge for iOS
                  if (Platform.isIOS) {
                    int currentBadge = await getBadgeCounter();
                    int newBadge = currentBadge + 1;
                    await updateBadgeCounter(newBadge);
                    print('[BG] Badge updated to: $newBadge');
                  }

                  await _markAsUnreadBackground(msg);
                  print('[BG] Message ${msg.id} marked as unread on server');
                } catch (e) {
                  print('[BG ERROR] Failed to process message ${msg.id}: $e');
                }
              }

              // Update shown message IDs
              if (newNotes.isNotEmpty) {
                final List<String> newIds = newNotes.map((m) => m.id).toList();
                await MessageStorage.addShownNoteIds(newIds);
                print('[BG] Saved ${newIds.length} new message IDs');
              }
            }
          } catch (e) {
            print('[BG ERROR] Notes check failed: $e');
          }

          // NOTIFICATION COUNTS CHECK
          print('[BG] === Starting NOTIFICATION COUNTS CHECK ===');

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
              print('[BG] New counts: S:${newCounts.submissions} W:${newCounts.watches} C:${newCounts.comments} F:${newCounts.favorites} J:${newCounts.journals} N:${newCounts.notes}');

              // Check user settings for enabled notifications
              final bool submissionsEnabled = prefs.getBool('drawer_notif_submissions_enabled') ?? true;
              final bool watchesEnabled = prefs.getBool('drawer_notif_watches_enabled') ?? true;
              final bool commentsEnabled = prefs.getBool('drawer_notif_comments_enabled') ?? true;
              final bool favoritesEnabled = prefs.getBool('drawer_notif_favorites_enabled') ?? true;
              final bool journalsEnabled = prefs.getBool('drawer_notif_journals_enabled') ?? true;
              final bool notesEnabled = prefs.getBool('drawer_notif_notes_enabled') ?? true;

              // Calculate sum based on enabled categories
              final int newSum = (submissionsEnabled ? newCounts.submissions : 0) +
                  (watchesEnabled ? newCounts.watches : 0) +
                  (commentsEnabled ? newCounts.comments : 0) +
                  (favoritesEnabled ? newCounts.favorites : 0) +
                  (journalsEnabled ? newCounts.journals : 0) +
                  (notesEnabled ? newCounts.notes : 0);

              final int previousSum = prefs.getInt(kPreviousSumKey) ?? 0;
              print('[BG] Sum comparison - Previous: $previousSum, New: $newSum');

              // Show notification if there's a change
              if (newSum != previousSum && newSum > 0) {
                final NotificationCounts filteredCounts = NotificationCounts(
                  submissions: submissionsEnabled ? newCounts.submissions : 0,
                  watches: watchesEnabled ? newCounts.watches : 0,
                  comments: commentsEnabled ? newCounts.comments : 0,
                  favorites: favoritesEnabled ? newCounts.favorites : 0,
                  journals: journalsEnabled ? newCounts.journals : 0,
                  notes: notesEnabled ? newCounts.notes : 0,
                );

                final String messageBody = _buildNotificationMessage(filteredCounts);

                if (messageBody.isNotEmpty) {
                  final bool soundActivitiesEnabled = prefs.getBool('sound_new_activities_enabled') ?? true;
                  final bool vibrationActivitiesEnabled = prefs.getBool('vibration_new_activities_enabled') ?? true;

                  if (soundActivitiesEnabled || vibrationActivitiesEnabled) {
                    await notificationService.showNotification(
                      999999,
                      'New FA Activity',
                      messageBody,
                      'activity_fa_activity',
                      'activities',
                    );
                    print('[BG] Activity notification shown: $messageBody');
                  }
                }

                await prefs.setInt(kPreviousSumKey, newSum);
                print('[BG] Previous sum updated to: $newSum');
              }
            } else {
              print('[BG] No notification data received from FA');
            }
          } catch (e) {
            print('[BG ERROR] Notification counts check failed: $e');
          }

          print('[BG] === Task completed successfully ===');
          print('[BG] Total duration: ${DateTime.now().difference(startTime).inSeconds}s');
          return Future.value(true);

        } catch (e, stackTrace) {
          print('[BG ERROR] Task failed: $e');
          print('[BG ERROR] Stack: $stackTrace');

          // Network errors should retry
          if (e.toString().contains('network') ||
              e.toString().contains('timeout') ||
              e.toString().contains('connection') ||
              e.toString().contains('SocketException')) {
            print('[BG] Network error detected - will retry');
            return Future.value(false);
          }

          print('[BG] Non-network error - marking as complete');
          return Future.value(true);
        }
      }

      print('[BG] Unknown task type: $task');
      return Future.value(true);

    } catch (e) {
      print('[BG FATAL ERROR] Callback dispatcher crash: $e');
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
  print('[$timestamp] $message');
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

// BACKGROUND NOTE FETCH
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
    print('[BG] No cookies found - user not logged in');
    throw Exception('Not logged in');
  }

  final result = <Message>[];
  for (int page = 1; page <= 2; page++) {
    final url = Uri.parse('https://www.furaffinity.net/msg/pms/$page/');

    final resp = await http.get(
      url,
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB; folder=inbox',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    );

    if (resp.statusCode == 200) {
      final decoded = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final doc = html_parser.parse(decoded);

      // Try modern layout first
      var noteElements = doc.querySelectorAll('.message-center-pms-note-list-view .note-list-container');

      if (noteElements.isEmpty) {
        noteElements = doc.querySelectorAll('#notes-list .note-list-container');
      }

      // Try classic layout
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
        final sender = noteEl.querySelector('.c-usernameBlock__displayName .js-displayName')?.text.trim() ??
            'Unknown sender';
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
    [Cookie('a', cookieA), Cookie('b', cookieB)],
  );

  final resp = await dio.get(
    'https://www.furaffinity.net$link',
    options: Options(
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
      validateStatus: (status) => status != null && status >= 200 && status < 400,
    ),
  );

  if (resp.statusCode == 200) {
    final doc = html_parser.parse(resp.data);

    // Try modern layout
    final modernContentElement = doc.querySelector('.section-body .user-submitted-links');
    if (modernContentElement != null) {
      modernContentElement.querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
          .forEach((e) => e.remove());

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

    // Try classic layout
    final classicContentElement = doc.querySelector('td.noteContent.alt1');
    if (classicContentElement != null) {
      classicContentElement
          .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
          .forEach((e) => e.remove());

      classicContentElement.querySelector('span[style*="color: #999999"]')?.remove();

      classicContentElement
          .querySelectorAll('a.auto_link_shortened')
          .forEach((anchor) {
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
    [Cookie('a', cookieA), Cookie('b', cookieB)],
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
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': 'https://www.furaffinity.net/msg/pms/$pNum/$mId/',
        'Origin': 'https://www.furaffinity.net',
      },
      followRedirects: false,
      validateStatus: (s) => s != null && (s == 302 || (s >= 200 && s < 300)),
    ),
  );
}

// Permission functions
Future<void> requestAndroidNotificationPermission() async {
  if (Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      final newStatus = await Permission.notification.request();
      print('Android notification permission: ${newStatus.isGranted ? "granted" : "denied"}');
    }
  }
}

Future<void> requestIOSNotificationPermission() async {
  if (Platform.isIOS) {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      final newStatus = await Permission.notification.request();
      print('iOS notification permission: ${newStatus.isGranted ? "granted" : "denied"}');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print("===============================================");
  print("APP STARTING: ${DateTime.now()}");
  print("===============================================");

  // Initialize basic services
  await PackageInfo.fromPlatform();
  final timezoneProvider = TimezoneProvider();
  await timezoneProvider.fetchTimezone();

  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.updateNotificationChannels();

  tz.initializeTimeZones();

  // Request permissions
  await requestAndroidNotificationPermission();
  await requestIOSNotificationPermission();

  // Handle notification launch
  final NotificationAppLaunchDetails? notificationAppLaunchDetails =
  await notificationService.flutterLocalNotificationsPlugin
      .getNotificationAppLaunchDetails();

  if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
    final payload = notificationAppLaunchDetails!.notificationResponse?.payload;
    if (payload != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_navigation', payload);
    }
  }

  // Initialize cache manager
  final cacheManager = CustomCacheManager();
  final cacheMonitorService = CacheMonitorService(cacheManager);
  await cacheMonitorService.checkStorageUsage();

  // CRITICAL: Initialize Workmanager BEFORE registering tasks
  print("Initializing Workmanager...");
  await Workmanager().initialize(callbackDispatcher);
  print("Workmanager initialized");

  // Register background tasks based on platform
  if (Platform.isAndroid) {
    await Workmanager().registerPeriodicTask(
      "FANotify",
      fetchBackgroundTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
    print("Android background task registered");
  } else if (Platform.isIOS) {
    print("iOS background task handler registered");
  }

  // Set initial app state
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool("isAppActive", true);
  print("App initial state set to ACTIVE");

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
        ChangeNotifierProvider<FANotificationService>(
          create: (_) => FANotificationService(),
        ),
      ],
      child: const MyApp(),
    ),
  );
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

    // Add periodic debug logging for state verification
    if (kDebugMode || true) { // Always log in release for debugging
      _stateDebugTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
        final prefs = await SharedPreferences.getInstance();
        final isActive = prefs.getBool("isAppActive") ?? false;
        print("[STATE CHECK] App active: $isActive at ${DateTime.now()}");
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('===============================================');
    print('APP LIFECYCLE CHANGED: $state');
    print('Time: ${DateTime.now()}');
    print('===============================================');

    switch (state) {
      case AppLifecycleState.resumed:
        _setAppActive(true);
        print('→ App RESUMED - Background fetch DISABLED');
        break;
      case AppLifecycleState.inactive:
      // Don't change state on inactive - it's transitional
        print('→ App INACTIVE (transitional state)');
        break;
      case AppLifecycleState.paused:
        _setAppActive(false);
        print('→ App PAUSED - Background fetch ENABLED');
        break;
      case AppLifecycleState.detached:
        _setAppActive(false);
        print('→ App DETACHED - Background fetch ENABLED');
        break;
      case AppLifecycleState.hidden:
        _setAppActive(false);
        print('→ App HIDDEN - Background fetch ENABLED');
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
      await prefs.reload(); // Force commit
      print("[APP STATE] Set to: ${active ? 'ACTIVE' : 'INACTIVE'}");

      if (active) {
        await resetBadgeCounter();
      }
    } catch (e) {
      print("[ERROR] Failed to set app state: $e");
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
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
GlobalKey<ScaffoldMessengerState>();
