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


final RouteObserver<ModalRoute<dynamic>> routeObserver = RouteObserver<ModalRoute<dynamic>>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String fetchBackgroundTask = "fetchBackgroundTask";
const String kPreviousSumKey = 'previousSumOfNotifications';

@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    await debugLogs('[CallbackDispatcher] START: Worker started for task: $task');
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await debugLogs('[CallbackDispatcher] SharedPreferences retrieved successfully.');
    } catch (e) {
      await debugLogs('[CallbackDispatcher] ERROR retrieving SharedPreferences: $e');
      return Future.value(false);
    }

    bool isAppActive;
    try {
      isAppActive = prefs.getBool("isAppActive") ?? false;
      await debugLogs('[CallbackDispatcher] App active flag from prefs: $isAppActive');
    } catch (e) {
      await debugLogs('[CallbackDispatcher] ERROR reading isAppActive flag: $e');
      return Future.value(false);
    }


    if (isAppActive) {
      await debugLogs('[CallbackDispatcher] App is active; skipping background fetch.');
      return Future.value(true);
    }

    if (task == fetchBackgroundTask || task == 'iOSPerformFetch') {
      await debugLogs('[CallbackDispatcher] Task matches fetchBackgroundTask or iOSPerformFetch, starting process.');

      try {

        // Unread Notes Check

        await debugLogs('[CallbackDispatcher] Starting UNREAD NOTES CHECK.');
        try {
          await prefs.reload();
          await debugLogs('[CallbackDispatcher] SharedPreferences reloaded.');
        } catch (e) {
          await debugLogs('[CallbackDispatcher] ERROR reloading SharedPreferences: $e');
        }

        bool didFirstRunSkip = prefs.getBool('did_first_run_skip') ?? false;
        await debugLogs('[CallbackDispatcher] did_first_run_skip flag: $didFirstRunSkip');
        if (!didFirstRunSkip) {
          await debugLogs('[CallbackDispatcher] First run skip not done; no notifications.');
          return Future.value(true);
        }

        final notificationService = NotificationService();
        await debugLogs('[CallbackDispatcher] Initializing NotificationService.');
        await notificationService.init();

        await debugLogs('[CallbackDispatcher] Fetching inbox messages.');
        final List<Message> fetchedInbox = await _fetchInboxTwoPagesBg();
        await debugLogs('[CallbackDispatcher] Fetched ${fetchedInbox.length} messages from inbox.');

        // Retrieving IDs that have already been processed
        final Set<String> shownSet = await MessageStorage.getShownNoteIds();
        await debugLogs('[CallbackDispatcher] Retrieved ${shownSet.length} shown message IDs.');

        // Filter unread messages
        final List<Message> unread = fetchedInbox.where((m) => m.isUnread).toList();
        await debugLogs('[CallbackDispatcher] Found ${unread.length} unread messages.');

        if (unread.isNotEmpty) {
          // Identify new messages that have not been shown before
          final List<Message> newNotes = unread.where((m) => !shownSet.contains(m.id)).toList();
          await debugLogs('[CallbackDispatcher] New unread messages count: ${newNotes.length}');

          // Processing each new unread message
          for (var msg in newNotes) {
            try {
              await debugLogs('[CallbackDispatcher] Processing message id: ${msg.id}');
              final String content = await _fetchMessageContentInBackground(msg.link);
              await debugLogs('[CallbackDispatcher] Fetched content for msg id: ${msg.id}');
              final String payload = 'note_${msg.id}';
              await debugLogs('[CallbackDispatcher] Showing notification for msg id: ${msg.id} with payload: $payload');

              // Show the notification
              await notificationService.showNotification(
                msg.id.hashCode,
                'New Note from ${msg.sender}',
                content,
                payload,
                'notes',
              );
              await debugLogs('[CallbackDispatcher] Notification shown for msg id: ${msg.id}');

              // Increment the badge counter for iOS only
              if (Platform.isIOS) {
                int currentBadge = await getBadgeCounter();
                int newBadge = currentBadge + 1;
                await updateBadgeCounter(newBadge);
              }

              await _markAsUnreadBackground(msg);
              await debugLogs('[CallbackDispatcher] Marked message id ${msg.id} as unread.');
            } catch (e) {
              await debugLogs('[CallbackDispatcher] ERROR processing message id ${msg.id}: $e');
            }
          }

          // Updating the list of shown message IDs
          final List<String> newIds = newNotes.map((m) => m.id).toList();
          await MessageStorage.addShownNoteIds(newIds);
          await debugLogs('[CallbackDispatcher] Updated shown message IDs: $newIds');
        } else {
          await debugLogs('[CallbackDispatcher] No unread messages found.');
        }


        // Notification Counts Check

        await debugLogs('[CallbackDispatcher] Starting NOTIFICATION COUNTS CHECK.');
        final faService = FaService();
        await debugLogs('[CallbackDispatcher] Fetching new notification counts from FA.');
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
          await debugLogs('[CallbackDispatcher] New notification counts: $newCounts');

          // Read user settings for enabled notification categories
          final bool submissionsEnabled = prefs.getBool('drawer_notif_submissions_enabled') ?? true;
          final bool watchesEnabled = prefs.getBool('drawer_notif_watches_enabled') ?? true;
          final bool commentsEnabled = prefs.getBool('drawer_notif_comments_enabled') ?? true;
          final bool favoritesEnabled = prefs.getBool('drawer_notif_favorites_enabled') ?? true;
          final bool journalsEnabled = prefs.getBool('drawer_notif_journals_enabled') ?? true;
          final bool notesEnabled = prefs.getBool('drawer_notif_notes_enabled') ?? true;

          // Calculate the sum count based on enabled categories
          final int newSum = (submissionsEnabled ? newCounts.submissions : 0) +
              (watchesEnabled ? newCounts.watches : 0) +
              (commentsEnabled ? newCounts.comments : 0) +
              (favoritesEnabled ? newCounts.favorites : 0) +
              (journalsEnabled ? newCounts.journals : 0) +
              (notesEnabled ? newCounts.notes : 0);
          await debugLogs('[CallbackDispatcher] Calculated new sum: $newSum');

          final int previousSum = prefs.getInt(kPreviousSumKey) ?? 0;
          await debugLogs('[CallbackDispatcher] Previous sum: $previousSum');

          // If there's a change, display the activity notification
          if (newSum != previousSum) {
            final NotificationCounts filteredCounts = NotificationCounts(
              submissions: submissionsEnabled ? newCounts.submissions : 0,
              watches: watchesEnabled ? newCounts.watches : 0,
              comments: commentsEnabled ? newCounts.comments : 0,
              favorites: favoritesEnabled ? newCounts.favorites : 0,
              journals: journalsEnabled ? newCounts.journals : 0,
              notes: notesEnabled ? newCounts.notes : 0,
            );
            final String messageBody = _buildNotificationMessage(filteredCounts);
            await debugLogs('[CallbackDispatcher] Built activity notification message: "$messageBody"');

            if (messageBody.isNotEmpty) {
              final bool soundActivitiesEnabled = prefs.getBool('sound_new_activities_enabled') ?? true;
              final bool vibrationActivitiesEnabled = prefs.getBool('vibration_new_activities_enabled') ?? true;
              if (soundActivitiesEnabled || vibrationActivitiesEnabled) {
                final String payload = 'activity_fa_activity';
                await debugLogs('[CallbackDispatcher] Displaying activity notification with payload: $payload');
                await notificationService.showNotification(
                  999999,
                  'New FA Activity',
                  messageBody,
                  payload,
                  'activities',
                );
                await debugLogs('[CallbackDispatcher] Activity notification displayed.');
              } else {
                await debugLogs('[CallbackDispatcher] Activity notifications are disabled; not displaying.');
              }
            } else {
              await debugLogs('[CallbackDispatcher] Notification message empty; nothing to display.');
            }

            await prefs.setInt(kPreviousSumKey, newSum);
            await debugLogs('[CallbackDispatcher] Updated previous sum to $newSum.');
          } else {
            await debugLogs('[CallbackDispatcher] Notification counts have not changed.');
          }
        } else {
          await debugLogs('[CallbackDispatcher] faService.fetchNotifications() returned null.');
        }

        await debugLogs('[CallbackDispatcher] Task completed successfully.');
        return Future.value(true);
      } catch (e) {
        await debugLogs('[CallbackDispatcher] Error in background task: $e');
        return Future.value(false);
      }
    }

    await debugLogs('[CallbackDispatcher] Unknown task received: $task');
    return Future.value(false);
  });
}


/// build a message "3S | 1W | 4C | 1F | 2J | 106N"
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
  try {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] $message');
  } catch (e) {
    print('Error writing log to console: $e');
  }
}

Future<int> getBadgeCounter() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt('badgeCounter') ?? 0;
}

Future<void> updateBadgeCounter(int newCount) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('badgeCounter', newCount);
  if (Platform.isIOS) {
    print("Updating badge count to: $newCount");
    FlutterAppBadgeControl.updateBadgeCount(newCount);
  }
}


Future<void> resetBadgeCounter() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('badgeCounter', 0);
  if (Platform.isIOS) {
    // Removing the badge from the app icon on iOS
    FlutterAppBadgeControl.removeBadge();
  }
}




// BACKGROUND NOTE FETCH
Future<List<Message>> _fetchInboxTwoPagesBg() async {
  final storage = const FlutterSecureStorage();


  final cookieA = await storage.read(key: 'fa_cookie_a');
  final cookieB = await storage.read(key: 'fa_cookie_b');


  if (cookieA == null || cookieB == null) {
    print('[ERRORnote] Missing cookies. Not logged in.');
    throw Exception('[Bgnote] no cookies => not logged in');
  }

  final result = <Message>[];
  for (int page = 1; page <= 2; page++) {
    print('[DEBUGnote] Fetching page $page.');
    final url = Uri.parse('https://www.furaffinity.net/msg/pms/$page/');
    print('[DEBUGnote] Constructed URL: $url');

    final resp = await http.get(
      url,
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB; folder=inbox',
        'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/95.0.4638.69 Safari/537.36',
      },
    );
    print('[DEBUGnote] Received response with status code: ${resp.statusCode}');

    if (resp.statusCode == 200) {
      final decoded = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final doc = html_parser.parse(decoded);

      // modern layout
      var noteElements =
      doc.querySelectorAll('.message-center-pms-note-list-view .note-list-container');

      if (noteElements.isEmpty) {
        noteElements = doc.querySelectorAll('#notes-list .note-list-container');
        print('[DEBUGnote] Fallback selector "#notes-list .note-list-container" found ${noteElements.length} elements.');
      }

      // classic layout
      if (noteElements.isEmpty) {
        final bool isClassic = doc.querySelector('body[data-static-path="/themes/classic"]') != null;
        print('[DEBUGnote] Checking classic layout: isClassic = $isClassic');
        if (isClassic) {
          List<dom.Element> classicRows = List.from(doc.querySelectorAll('#notes-list tr.note'));
          print('[DEBUGnote] Classic layout: found ${classicRows.length} note rows before removal check.');
          if (classicRows.isNotEmpty &&
              classicRows.last.querySelector('input[type="checkbox"]') == null) {
            print('[DEBUGnote] Removing trailing row from classic layout as it lacks a checkbox.');
            classicRows.removeLast();
          }
          noteElements = classicRows;
          print('[DEBUGnote] Classic layout: ${noteElements.length} note rows after removal check.');
        } else {

          noteElements = doc.querySelectorAll('td.note-list-container tr.note');
          print('[DEBUGnote] Fallback layout selector "td.note-list-container tr.note" found ${noteElements.length} elements.');
        }
      }

      if (noteElements.isEmpty) {
        print('[DEBUGnote] No note elements found on page $page. Exiting loop.');
        break;
      }

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
      print('[ERRORnote] HTTP request failed for page $page with status code ${resp.statusCode}.');
      throw Exception('[Bgnote] fail => page $page, code ${resp.statusCode}');
    }
  }
  print('[DEBUGnote] Finished fetching messages. Total messages fetched: ${result.length}');
  return result;
}

Future<String> _fetchMessageContentInBackground(String link) async {
  final storage = const FlutterSecureStorage();
  final cookieA = await storage.read(key: 'fa_cookie_a');
  final cookieB = await storage.read(key: 'fa_cookie_b');
  if (cookieA == null || cookieB == null) {
    throw Exception('[Bg] no cookies => not logged in');
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
        'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/95.0.4638.69 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
      validateStatus: (status) => status != null && status >= 200 && status < 400,
    ),
  );

  if (resp.statusCode == 200) {
    final doc = html_parser.parse(resp.data);

    // Remove scam warning.
    doc.querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
        .forEach((element) => element.remove());

    // modern layout
    final modernContentElement = doc.querySelector('.section-body .user-submitted-links');
    if (modernContentElement != null) {

      modernContentElement.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
        final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
        if (fullLink != null) {
          anchor.innerHtml = fullLink;
        }
      });
      final content = modernContentElement.text.trim();
      final newestContent = extractNewestContent(content);
      return newestContent.isNotEmpty ? newestContent : 'No content';
    } else {
      // classic layout
      final classicContentElement = doc.querySelector('td.noteContent.alt1');
      if (classicContentElement != null) {

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
    }
    return 'No content';
  } else {
    throw Exception('[Bg] _fetchMessageContent => code ${resp.statusCode}');
  }
}

Future<void> _markAsUnreadBackground(Message msg) async {
  final storage = const FlutterSecureStorage();
  final cookieA = await storage.read(key: 'fa_cookie_a');
  final cookieB = await storage.read(key: 'fa_cookie_b');
  if (cookieA == null || cookieB == null) {
    throw Exception('[Bg] no cookies => not logged in');
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
      pNum = 1; // Classic messages don't have a page number.
    } else {
      throw Exception('[Bg] invalid msg ID => cannot mark unread');
    }
  }

  final formData = {
    'manage_notes': '1',
    'items[]': mId,
    'move_to': 'unread',
  };

  final response = await dio.post(
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
  if (response.statusCode == 302 || response.statusCode == 200) {
    print('[Bg] re-marked ${msg.id} => unread');
  } else {
    print('[Bg] failed marking unread => ${response.statusCode}');
  }
}

// PERMISSION FUNCTIONS
Future<void> requestAndroidNotificationPermission() async {
  if (Platform.isAndroid) {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      final newStatus = await Permission.notification.request();
      if (newStatus.isGranted) {
        print('Android notification permission granted');
      } else {
        print('Android notification permission denied');
      }
    } else if (status.isGranted) {
      print('Android notification permission already granted');
    }
  }
}

// iOS-specific permission request
Future<void> requestIOSNotificationPermission() async {
  if (Platform.isIOS) {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      final newStatus = await Permission.notification.request();
      if (newStatus.isGranted) {
        print('iOS notification permission granted');
      } else {
        print('iOS notification permission denied');
      }
    } else if (status.isGranted) {
      print('iOS notification permission already granted');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final timezoneProvider = TimezoneProvider();
  // Fetch timezone data once
  await timezoneProvider.fetchTimezone();

  final notificationService = NotificationService();
  await notificationService.init();
  await notificationService.updateNotificationChannels();

  tz.initializeTimeZones();

  // Request Android and iOS permission
  await requestAndroidNotificationPermission();
  await requestIOSNotificationPermission();

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

  final cacheManager = CustomCacheManager();
  final cacheMonitorService = CacheMonitorService(cacheManager);
  await cacheMonitorService.checkStorageUsage();

  // WorkManager init
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  // Periodic background fetch
  Workmanager().registerPeriodicTask(
    "FANotify",
    fetchBackgroundTask,
    frequency: const Duration(minutes: 15),
    initialDelay: const Duration(seconds: 10),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setAppActive(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setAppActive(false);
    super.dispose();
  }

  Future<void> _setAppActive(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("isAppActive", active);
    if (active) {
      // When the app becomes active, reset the badge counter and remove the badge
      await resetBadgeCounter();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setAppActive(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FA Notify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      home: const HomeScreen(),
    );
  }
}