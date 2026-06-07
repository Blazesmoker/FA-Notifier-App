import 'dart:io';
import 'dart:convert';
import 'package:FANotifier/features/notifications/data/NotificationNavigationProvider.dart';
import 'package:FANotifier/features/settings/data/timezone_provider.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/core/cache/CacheMonitorService.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_service.dart';
import 'package:FANotifier/features/notifications/data/pending_navigation.dart';
import 'package:FANotifier/shared/utils/notes_notifications_text_edit.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
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
import 'package:FANotifier/app/analytics_privacy.dart';
import 'package:FANotifier/core/cache/custom_cache_manager.dart';
import 'package:FANotifier/features/drawer/presentation/drawer_user_controller.dart';
import 'package:FANotifier/features/drawer/data/app_update_service.dart';
import 'package:FANotifier/features/drawer/presentation/update_screen.dart';
import 'package:FANotifier/features/notifications/data/activities_notification_state.dart';
import 'package:FANotifier/features/notifications/data/notification_service.dart';
import 'package:FANotifier/core/utils/utils.dart';
import 'package:FANotifier/features/notes/data/message_storage.dart';
import 'package:FANotifier/features/home/presentation/home_screen.dart';
import 'package:FANotifier/app/app_theme.dart';
import 'package:FANotifier/features/notifications/data/notification_settings_provider.dart';
import 'package:FANotifier/features/settings/data/thumbnail_display_settings_provider.dart';
import 'package:FANotifier/features/settings/data/translator_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:FANotifier/features/notifications/domain/notification_counts.dart';
import 'package:html/dom.dart' as dom;
import 'package:FANotifier/shared/utils/fa_link_handler.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:FANotifier/core/logging/app_logging.dart';

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

final RouteObserver<ModalRoute<dynamic>> routeObserver =
    RouteObserver<ModalRoute<dynamic>>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<DrawerUserControllerState> drawerKey =
    GlobalKey<DrawerUserControllerState>();

const String fetchBackgroundTask = "fetchBackgroundTask";
const String iOSWorkInitTask = "com.blazesmoker.FANotifier.refresh";
bool _workmanagerInitialized = false;
const String _appActiveKey = 'isAppActive';
const String _appActiveAtMsKey = 'isAppActiveAtMs';
const Duration _appActiveLease = Duration(minutes: 2);
const bool _forceShowUpdateScreen = false;

bool _isAppForegroundActive(SharedPreferences prefs) {
  if (!(prefs.getBool(_appActiveKey) ?? false)) return false;
  final activeAtMs = prefs.getInt(_appActiveAtMsKey);
  if (activeAtMs == null) return false;
  final ageMs = DateTime.now().millisecondsSinceEpoch - activeAtMs;
  return ageMs >= 0 && ageMs <= _appActiveLease.inMilliseconds;
}

Future<void> _persistAppForegroundState(bool active) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_appActiveKey, active);
  if (active) {
    await prefs.setInt(
      _appActiveAtMsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  } else {
    await prefs.remove(_appActiveAtMsKey);
  }
}

Future<void> ensureWorkmanagerInitialized() async {
  if (_workmanagerInitialized) return;
  debugPrint("Initializing Workmanager...");
  await Workmanager().initialize(callbackDispatcher);
  _workmanagerInitialized = true;
  debugPrint("Workmanager initialized");
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppLogging();
  Workmanager().executeTask((task, inputData) async {
    appLog("===============================================");
    appLog("BACKGROUND TASK TRIGGERED: $task");
    appLog("Time: ${DateTime.now()}");
    appLog("===============================================");
    final startTime = DateTime.now();
    try {
      final notificationService = NotificationService();
      await notificationService.init();
      appLog("[BG] NotificationService initialized");
      SharedPreferences prefs;
      try {
        prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        appLog('[BG] SharedPreferences loaded successfully');
        await FAHttp.initFromPrefs(prefs: prefs);
        HttpOverrides.global = FreshHttpOverrides();
      } catch (e) {
        appLog('[BG ERROR] Failed to load SharedPreferences: $e');
        return Future.value(false);
      }
      final bool isAppActive = _isAppForegroundActive(prefs);
      appLog('[BG] App active status: $isAppActive');
      if (isAppActive) {
        appLog('[BG] App is ACTIVE - skipping background fetch');
        appLog(
            '[BG] Task completed (skipped) in ${DateTime.now().difference(startTime).inSeconds}s');
        return Future.value(true);
      }
      appLog('[BG] App is INACTIVE - proceeding with background fetch');
      if (task == fetchBackgroundTask ||
          task == iOSWorkInitTask ||
          task == Workmanager.iOSBackgroundTask) {
        appLog('[BG] Valid background task detected: $task');
        try {
          final currentVersionAllowed = await isCurrentAppVersionAllowed();
          if (currentVersionAllowed == false) {
            appLog('[BG] Current app version is not allowed - skipping fetch');
            return Future.value(true);
          }
          bool didFirstRunSkip = prefs.getBool('did_first_run_skip') ?? false;
          appLog('[BG] First run skip status: $didFirstRunSkip');
          if (!didFirstRunSkip) {
            appLog('[BG] First run not complete - skipping notifications');
            return Future.value(true);
          }
          NotificationCounts? currentCounts;

          appLog('[BG] === Starting UNREAD NOTES CHECK ===');
          try {
            final Set<String> shownSet = await MessageStorage.getShownNoteIds();
            final Set<String> seenSet = await MessageStorage.getSeenNoteIds();
            final _BackgroundInboxSnapshot snapshot =
                await _fetchInboxSnapshotBg(
              shownNoteIds: shownSet,
              seenNoteIds: seenSet,
            );
            final List<Message> fetchedInbox = snapshot.messages;
            currentCounts = snapshot.topbarCounts;
            await prefs.reload();
            if (_isAppForegroundActive(prefs)) {
              return Future.value(true);
            }
            kDebugPrint(
              '[BG] Fetched ${fetchedInbox.length} messages from inbox '
              '(page2=${snapshot.fetchedPage2})',
            );
            kDebugPrint(
                '[BG] Already shown: ${shownSet.length} message IDs; seen: ${seenSet.length}');
            if (currentCounts != null) {
              final countsForLog = currentCounts;
              kDebugPrint(
                  '[BG] Page 1 topbar counts: S:${countsForLog.submissions} W:${countsForLog.watches} C:${countsForLog.comments} F:${countsForLog.favorites} J:${countsForLog.journals} N:${countsForLog.notes}');
            } else {
              appLog('[BG] Page 1 topbar counts unavailable.');
            }
            final List<Message> unread =
                fetchedInbox.where((m) => m.isUnread).toList();
            kDebugPrint('[BG] Found ${unread.length} unread messages');
            if (unread.isNotEmpty) {
              final List<Message> newNotes =
                  unread.where((m) => !shownSet.contains(m.id)).toList();
              kDebugPrint('[BG] New unread messages: ${newNotes.length}');
              final List<String> shownNewNoteIds = <String>[];
              for (var msg in newNotes) {
                try {
                  kDebugPrint(
                      '[BG] Processing message: ${msg.id} from ${msg.sender}');
                  final String content =
                      await _fetchMessageContentInBackground(msg.link);
                  await prefs.reload();
                  if (_isAppForegroundActive(prefs)) {
                    return Future.value(true);
                  }
                  final String payload = 'note_${msg.id}';
                  final int? badgeNumber =
                      await nextIOSBadgeNumberForNotification();
                  await notificationService.showNotification(
                    stableNotificationIdFromString(msg.id),
                    'New Note from ${msg.sender}',
                    content,
                    payload,
                    'notes',
                    badgeNumber: badgeNumber,
                  );
                  await commitIOSBadgeNumber(badgeNumber);
                  shownNewNoteIds.add(msg.id);
                  kDebugPrint('[BG] Notification shown for message ${msg.id}');
                  if (badgeNumber != null) {
                    kDebugPrint('[BG] Badge updated to: $badgeNumber');
                  }
                  await _markAsUnreadBackground(msg);
                  kDebugPrint(
                      '[BG] Message ${msg.id} marked as unread on server');
                } catch (e) {
                  kDebugPrint(
                      '[BG ERROR] Failed to process message ${msg.id}: $e');
                }
              }
              if (shownNewNoteIds.isNotEmpty) {
                await MessageStorage.addShownNoteIds(shownNewNoteIds);
                kDebugPrint(
                    '[BG] Saved ${shownNewNoteIds.length} new message IDs');
              }
            }
            final fetchedIds = fetchedInbox.map((m) => m.id).toList();
            if (fetchedIds.isNotEmpty) {
              await MessageStorage.addSeenNoteIds(fetchedIds);
              kDebugPrint('[BG] Saved ${fetchedIds.length} seen message IDs');
            }
          } catch (e) {
            appLog('[BG ERROR] Notes check failed: $e');
          }
          appLog('[BG] === Starting NOTIFICATION COUNTS CHECK ===');
          try {
            final counts = currentCounts;
            if (counts != null) {
              kDebugPrint(
                  '[BG] New counts: S:${counts.submissions} W:${counts.watches} C:${counts.comments} F:${counts.favorites} J:${counts.journals} N:${counts.notes}');
              final bool submissionsEnabled =
                  prefs.getBool('drawer_notif_submissions_enabled') ?? true;
              final bool watchesEnabled =
                  prefs.getBool('drawer_notif_watches_enabled') ?? true;
              final bool commentsEnabled =
                  prefs.getBool('drawer_notif_comments_enabled') ?? true;
              final bool favoritesEnabled =
                  prefs.getBool('drawer_notif_favorites_enabled') ?? true;
              final bool journalsEnabled =
                  prefs.getBool('drawer_notif_journals_enabled') ?? true;
              final bool notesEnabled =
                  prefs.getBool('drawer_notif_notes_enabled') ?? true;

              final activitiesStateStore = ActivitiesNotificationStateStore();
              final ActivitiesDiff diff = await activitiesStateStore
                  .diffFromAcknowledged(currentCounts: counts);
              kDebugPrint(
                  '[BG] Last-seen counts: S:${diff.previous.submissions} W:${diff.previous.watches} C:${diff.previous.comments} F:${diff.previous.favorites} J:${diff.previous.journals} N:${diff.previous.notes}');
              kDebugPrint(
                  '[BG] Increased by:     S:${diff.increasedBy.submissions} W:${diff.increasedBy.watches} C:${diff.increasedBy.comments} F:${diff.increasedBy.favorites} J:${diff.increasedBy.journals} N:${diff.increasedBy.notes}');

              final NotificationCounts enabledIncreases = NotificationCounts(
                submissions:
                    submissionsEnabled ? diff.increasedBy.submissions : 0,
                watches: watchesEnabled ? diff.increasedBy.watches : 0,
                comments: commentsEnabled ? diff.increasedBy.comments : 0,
                favorites: favoritesEnabled ? diff.increasedBy.favorites : 0,
                journals: journalsEnabled ? diff.increasedBy.journals : 0,
                notes: notesEnabled ? diff.increasedBy.notes : 0,
              );

              final bool hasEnabledIncrease =
                  enabledIncreases.submissions > 0 ||
                      enabledIncreases.watches > 0 ||
                      enabledIncreases.comments > 0 ||
                      enabledIncreases.favorites > 0 ||
                      enabledIncreases.journals > 0 ||
                      enabledIncreases.notes > 0;
              final bool shouldNotify = hasEnabledIncrease;

              final NotificationCounts filteredCounts = NotificationCounts(
                submissions: submissionsEnabled ? counts.submissions : 0,
                watches: watchesEnabled ? counts.watches : 0,
                comments: commentsEnabled ? counts.comments : 0,
                favorites: favoritesEnabled ? counts.favorites : 0,
                journals: journalsEnabled ? counts.journals : 0,
                notes: notesEnabled ? counts.notes : 0,
              );
              final String messageBody = _buildNotificationMessage(
                filteredCounts,
                enabledIncreases,
              );

              if (shouldNotify) {
                final bool soundActivitiesEnabled =
                    prefs.getBool('sound_new_activities_enabled') ?? true;
                final bool vibrationActivitiesEnabled =
                    prefs.getBool('vibration_new_activities_enabled') ?? true;
                if (soundActivitiesEnabled || vibrationActivitiesEnabled) {
                  final bool isDuplicate =
                      await activitiesStateStore.areCurrentCountsLastShown(
                    currentCounts: counts,
                  );
                  if (isDuplicate) {
                    appLog(
                        '[BG] Duplicate activity notification skipped: $messageBody');
                  } else if (!messageBody.contains('(+')) {
                    await activitiesStateStore.acknowledgeCurrentCounts(
                      currentCounts: counts,
                    );
                  } else {
                    await prefs.reload();
                    if (_isAppForegroundActive(prefs)) {
                      return Future.value(true);
                    }
                    final int? badgeNumber =
                        await nextIOSBadgeNumberForNotification();
                    await notificationService.showNotification(
                      NotificationService.activityNotificationId,
                      'New FA Activity',
                      messageBody,
                      'activity_fa_activity',
                      'activities',
                      badgeNumber: badgeNumber,
                    );
                    await prefs.reload();
                    if (_isAppForegroundActive(prefs)) {
                      await notificationService.cancelActivityNotification();
                      return Future.value(true);
                    }
                    await commitIOSBadgeNumber(badgeNumber);
                    await activitiesStateStore.markActivityNotificationShown(
                      currentCounts: counts,
                      body: messageBody,
                    );
                    appLog('[BG] Activity notification shown.');
                    kDebugPrint(
                        '[BG] Activity notification shown: $messageBody');
                  }
                } else {
                  appLog(
                      '[BG] Activities sound+vibration disabled; not showing notification.');
                  await activitiesStateStore.acknowledgeCurrentCounts(
                    currentCounts: counts,
                  );
                }
              } else {
                appLog('[BG] No enabled category increased; not notifying.');
                if (diff.hasAnyIncrease) {
                  await activitiesStateStore.acknowledgeCurrentCounts(
                    currentCounts: counts,
                  );
                }
              }
            } else {
              appLog('[BG] No notification data received from FA');
            }
          } catch (e) {
            appLog('[BG ERROR] Notification counts check failed: $e');
          }
          appLog('[BG] === Task completed successfully ===');
          appLog(
              '[BG] Total duration: ${DateTime.now().difference(startTime).inSeconds}s');
          return Future.value(true);
        } catch (e, stackTrace) {
          appLog('[BG ERROR] Task failed: $e');
          kDebugPrint('[BG ERROR] Stack: $stackTrace');
          if (e.toString().contains('network') ||
              e.toString().contains('timeout') ||
              e.toString().contains('connection') ||
              e.toString().contains('SocketException')) {
            appLog('[BG] Network error detected - will retry');
            return Future.value(false);
          }
          appLog('[BG] Non-network error - marking as complete');
          return Future.value(true);
        }
      }
      appLog('[BG] Unknown task type: $task');
      return Future.value(true);
    } catch (e) {
      appLog('[BG FATAL ERROR] Callback dispatcher crash: $e');
      return Future.value(false);
    }
  });
}

String _formatNotificationPart({
  required int current,
  required int increasedBy,
  required String suffix,
}) {
  if (current <= 0) return '';
  if (increasedBy > 0) {
    return '$current$suffix(+$increasedBy)';
  }
  return '$current$suffix';
}

String _buildNotificationMessage(
  NotificationCounts counts,
  NotificationCounts increases,
) {
  final parts = <String>[];
  final submissions = _formatNotificationPart(
    current: counts.submissions,
    increasedBy: increases.submissions,
    suffix: 'S',
  );
  if (submissions.isNotEmpty) parts.add(submissions);
  final watches = _formatNotificationPart(
    current: counts.watches,
    increasedBy: increases.watches,
    suffix: 'W',
  );
  if (watches.isNotEmpty) parts.add(watches);
  final comments = _formatNotificationPart(
    current: counts.comments,
    increasedBy: increases.comments,
    suffix: 'C',
  );
  if (comments.isNotEmpty) parts.add(comments);
  final favorites = _formatNotificationPart(
    current: counts.favorites,
    increasedBy: increases.favorites,
    suffix: 'F',
  );
  if (favorites.isNotEmpty) parts.add(favorites);
  final journals = _formatNotificationPart(
    current: counts.journals,
    increasedBy: increases.journals,
    suffix: 'J',
  );
  if (journals.isNotEmpty) parts.add(journals);
  final notes = _formatNotificationPart(
    current: counts.notes,
    increasedBy: increases.notes,
    suffix: 'N',
  );
  if (notes.isNotEmpty) parts.add(notes);
  return parts.join(' | ');
}

Future<void> debugLogs(String message) async {
  final timestamp = DateTime.now().toIso8601String();
  debugPrint('[$timestamp] $message');
}

Future<int> getBadgeCounter() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getInt('badgeCounter') ?? 0;
}

Future<int?> nextIOSBadgeNumberForNotification() async {
  if (!Platform.isIOS) return null;
  return await getBadgeCounter() + 1;
}

Future<void> commitIOSBadgeNumber(int? badgeNumber) async {
  if (badgeNumber == null) return;
  await updateBadgeCounter(badgeNumber);
}

Future<void> updateBadgeCounter(int newCount) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('badgeCounter', newCount);
  if (Platform.isIOS) {
    try {
      await FlutterAppBadgeControl.updateBadgeCount(newCount);
    } catch (e) {
      appLog('[BADGE] Failed to update iOS app badge: $e');
    }
  }
}

Future<void> resetBadgeCounter() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('badgeCounter', 0);
  if (Platform.isIOS) {
    try {
      await FlutterAppBadgeControl.removeBadge();
    } catch (e) {
      appLog('[BADGE] Failed to clear iOS app badge: $e');
    }
  }
}

int stableNotificationIdFromString(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x3fffffff;
  }
  return hash == 0 ? 1 : hash;
}

class _BackgroundInboxSnapshot {
  const _BackgroundInboxSnapshot({
    required this.messages,
    required this.topbarCounts,
    required this.fetchedPage2,
  });

  final List<Message> messages;
  final NotificationCounts? topbarCounts;
  final bool fetchedPage2;
}

class _ParsedInboxPage {
  const _ParsedInboxPage({
    required this.messages,
    required this.topbarCounts,
  });

  final List<Message> messages;
  final NotificationCounts? topbarCounts;
}

Future<_BackgroundInboxSnapshot> _fetchInboxSnapshotBg({
  required Set<String> shownNoteIds,
  required Set<String> seenNoteIds,
}) async {
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

  final page1 = await _fetchInboxPageBg(
    page: 1,
    cookieA: cookieA,
    cookieB: cookieB,
  );
  final result = <Message>[...page1.messages];
  var fetchedPage2 = false;

  if (_shouldFetchInboxPage2Bg(
    page1: page1,
    shownNoteIds: shownNoteIds,
    seenNoteIds: seenNoteIds,
  )) {
    final page2 = await _fetchInboxPageBg(
      page: 2,
      cookieA: cookieA,
      cookieB: cookieB,
    );
    result.addAll(page2.messages);
    fetchedPage2 = true;
  }

  return _BackgroundInboxSnapshot(
    messages: result,
    topbarCounts: page1.topbarCounts,
    fetchedPage2: fetchedPage2,
  );
}

bool _shouldFetchInboxPage2Bg({
  required _ParsedInboxPage page1,
  required Set<String> shownNoteIds,
  required Set<String> seenNoteIds,
}) {
  if (page1.messages.isEmpty) return false;

  final knownIds = <String>{...shownNoteIds, ...seenNoteIds};
  final allPage1RowsAreBrandNewUnread = page1.messages.every((message) {
    if (!message.isUnread) return false;
    if (message.id.trim().isEmpty) return false;
    return !knownIds.contains(message.id);
  });
  if (!allPage1RowsAreBrandNewUnread) return false;

  final topbarNotes = page1.topbarCounts?.notes;
  if (topbarNotes != null) {
    final page1UnreadCount = page1.messages.where((m) => m.isUnread).length;
    if (topbarNotes <= page1UnreadCount) return false;
  }

  return true;
}

Future<_ParsedInboxPage> _fetchInboxPageBg({
  required int page,
  required String cookieA,
  required String cookieB,
}) async {
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
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}');
  }

  final decoded = utf8.decode(resp.bodyBytes, allowMalformed: true);
  final doc = html_parser.parse(decoded);
  return _ParsedInboxPage(
    messages: _parseInboxMessagesBg(doc),
    topbarCounts: page == 1 ? _parseTopbarCountsBg(doc) : null,
  );
}

List<Message> _parseInboxMessagesBg(dom.Document doc) {
  var noteElements = doc.querySelectorAll(
      '.message-center-pms-note-list-view .note-list-container');
  if (noteElements.isEmpty) {
    noteElements = doc.querySelectorAll('#notes-list .note-list-container');
  }
  if (noteElements.isEmpty) {
    final bool isClassic =
        doc.querySelector('body[data-static-path="/themes/classic"]') != null;
    if (isClassic) {
      List<dom.Element> classicRows =
          List.from(doc.querySelectorAll('#notes-list tr.note'));
      if (classicRows.isNotEmpty &&
          classicRows.last.querySelector('input[type="checkbox"]') == null) {
        classicRows.removeLast();
      }
      noteElements = classicRows;
    } else {
      noteElements = doc.querySelectorAll('td.note-list-container tr.note');
    }
  }

  final result = <Message>[];
  for (var noteEl in noteElements) {
    final subject = noteEl
            .querySelector(
                '.note-list-subject-container .c-noteListItem__subject')
            ?.text
            .trim() ??
        noteEl.querySelector('a.notelink.note-read.read')?.text.trim() ??
        noteEl.querySelector('a.notelink.note-unread.unread')?.text.trim() ??
        noteEl.querySelector('a.notelink')?.text.trim() ??
        'No subject';
    final sender = noteEl
            .querySelector('.c-usernameBlock__displayName .js-displayName')
            ?.text
            .trim() ??
        noteEl
            .querySelector(
                'div.c-usernameBlock.marquee-container a.c-usernameBlock__displayName.js-displayName-block span.js-displayName')
            ?.text
            .trim() ??
        'Unknown sender';
    final aTag = noteEl.querySelector('.note-list-subject-container a') ??
        noteEl.querySelector('a.notelink.note-unread.unread') ??
        noteEl.querySelector('a.notelink.note-read.read') ??
        noteEl.querySelector('a.notelink');
    final classicLink = aTag?.attributes['href'] ?? '';
    final String link = classicLink.startsWith('/viewmessage/')
        ? classicLink
        : (aTag?.attributes['newhref'] ?? classicLink);
    final checkbox = noteEl.querySelector('input[type="checkbox"]');
    final idFromLink = extractMessageId(link);
    final id = idFromLink.isNotEmpty
        ? idFromLink
        : (checkbox?.attributes['value'] ??
            (link.isNotEmpty ? link : '$sender|$subject|unknown-date'));
    final date =
        noteEl.querySelector('.note-list-senddate span')?.attributes['title'] ??
            noteEl
                .querySelector('td.alt1.nowrap span.popup_date')
                ?.attributes['title'] ??
            noteEl.querySelector('span.popup_date')?.attributes['title'] ??
            'Unknown date';
    final isUnread = noteEl.querySelector('img.unread') != null ||
        noteEl.querySelector('img[src*="pms-unread.png"]') != null ||
        noteEl.querySelector('a.notelink.note-unread.unread') != null;
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
  return result;
}

NotificationCounts? _parseTopbarCountsBg(dom.Document doc) {
  final links = doc.querySelectorAll(
      'li.message-bar-desktop a.notification-container, li.noblock a.notification-container');
  if (links.isEmpty) return null;

  final counts = <String, int>{
    'S': 0,
    'W': 0,
    'C': 0,
    'F': 0,
    'J': 0,
    'N': 0,
  };
  for (final link in links) {
    final href = link.attributes['href'] ?? '';
    final title = (link.attributes['title'] ?? '').trim();
    final text = link.text.trim();
    final key = _topbarTypeKeyBg(href: href, title: title);
    if (key == null) continue;
    counts[key] = _extractTopbarCountBg(title.isNotEmpty ? title : text);
  }

  return NotificationCounts(
    submissions: counts['S'] ?? 0,
    watches: counts['W'] ?? 0,
    comments: counts['C'] ?? 0,
    favorites: counts['F'] ?? 0,
    journals: counts['J'] ?? 0,
    notes: counts['N'] ?? 0,
  );
}

String? _topbarTypeKeyBg({
  required String href,
  required String title,
}) {
  final h = href.toLowerCase();
  final t = title.toLowerCase();
  if (h.contains('msg/submissions') || t.contains('submission')) return 'S';
  if (h.contains('#watches') || t.contains('watch')) return 'W';
  if (h.contains('#comments') || t.contains('comment')) return 'C';
  if (h.contains('#favorites') || t.contains('favorite')) return 'F';
  if (h.contains('#journals') || t.contains('journal')) return 'J';
  if (h.contains('msg/pms') || t.contains('note')) return 'N';
  return null;
}

int _extractTopbarCountBg(String text) {
  final match = RegExp(r'\d{1,3}(?:[,.]\d{3})*|\d+').firstMatch(text);
  if (match == null) return 0;
  return int.tryParse(match.group(0)!.replaceAll(RegExp(r'[,.]'), '')) ?? 0;
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
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  );
  if (resp.statusCode == 200) {
    final doc = html_parser.parse(resp.data);
    final modernContentElement =
        doc.querySelector('.section-body .user-submitted-links');
    if (modernContentElement != null) {
      modernContentElement
          .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
          .forEach((e) => e.remove());
      modernContentElement
          .querySelectorAll('a.auto_link_shortened')
          .forEach((anchor) {
        final fullLink =
            anchor.attributes['title'] ?? anchor.attributes['href'];
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
      classicContentElement
          .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
          .forEach((e) => e.remove());
      classicContentElement
          .querySelector('span[style*="color: #999999"]')
          ?.remove();
      classicContentElement
          .querySelectorAll('a.auto_link_shortened')
          .forEach((anchor) {
        final fullLink =
            anchor.attributes['title'] ?? anchor.attributes['href'];
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
      debugPrint(
          'Android notification permission: ${newStatus.isGranted ? "granted" : "denied"}');
    }
  }
}

Future<void> requestIOSNotificationPermission() async {
  if (Platform.isIOS) {
    final status = await Permission.notification.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      final newStatus = await Permission.notification.request();
      debugPrint(
          'iOS notification permission: ${newStatus.isGranted ? "granted" : "denied"}');
    }
  }
}

Future<void> _afterFirstFrameBoot(TimezoneProvider timezoneProvider) async {
  try {
    await PackageInfo.fromPlatform();
    tz.initializeTimeZones();
    await timezoneProvider.fetchTimezone();
    final notificationService = NotificationService();
    await notificationService.init(
      onLaunchPayloadSaved: () =>
          processPendingNavigation(from: 'notification_launch_details'),
    );
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
    await ensureWorkmanagerInitialized();
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
  } catch (e, st) {
    debugPrint('[BOOT] afterFirstFrame error: $e');
    debugPrint(st as String?);
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppLogging();
  await Firebase.initializeApp();
  await setupAnalyticsPrivacy();
  await FAHttp.init();
  AppLifecycleNetworkReset.attach();
  HttpOverrides.global = FreshHttpOverrides();
  try {
    await ensureWorkmanagerInitialized();
  } catch (e, st) {
    debugPrint('[BOOT] early Workmanager init failed: $e');
    debugPrint(st.toString());
  }
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
        ChangeNotifierProvider<TranslatorSettingsProvider>(
          create: (_) => TranslatorSettingsProvider(),
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
    debugPrint(
        '[BOOT] First frame at ${DateTime.now()} (+${DateTime.now().difference(t0)})');
    await _afterFirstFrameBoot(timezoneProvider);
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
          await processPendingNavigation(from: 'app_lifecycle_resumed');
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
        await _persistAppForegroundState(stateToPersist);
        appLog(
            "[APP STATE] Set to: ${stateToPersist ? 'ACTIVE' : 'INACTIVE'}");
        if (stateToPersist && shouldResetBadge && _desiredAppActive) {
          await resetBadgeCounter();
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
      title: 'FA Notify',
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

final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
