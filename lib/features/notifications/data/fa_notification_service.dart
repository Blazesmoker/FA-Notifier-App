import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/notifications/domain/notifications.dart';
import 'package:FANotifier/features/notifications/domain/notification_counts.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

/// A semaphore to limit concurrent network requests.
class SimpleSemaphore {
  int _available;
  final Queue<Completer<void>> _waitQueue = Queue();

  SimpleSemaphore(this._available);

  Future<void> acquire() {
    if (_available > 0) {
      _available--;
      return Future.value();
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _available++;
    }
  }
}

/// Model representing one Shout.
class Shout {
  final String id;
  final String nickname; // e.g. "UserName" for display
  final String nicknameLink; // e.g. "username" parsed from href
  final String postedTitle; // e.g. "Mar 6, 2025 07:34 PM"
  final String avatarUrl; // Avatar from user profile
  final String postedAgo; // e.g. "a few minutes ago"
  final String textContent; // The actual text of the shout (or "removed")
  bool isChecked;
  final bool isRemoved;

  Shout({
    required this.id,
    required this.nickname,
    required this.nicknameLink,
    required this.postedTitle,
    required this.avatarUrl,
    required this.postedAgo,
    required this.textContent,
    required this.isRemoved,
    this.isChecked = false,
  });

  @override
  String toString() {
    return 'Shout(id=$id, nickname=$nickname, postedTitle=$postedTitle, removed=$isRemoved, text="$textContent")';
  }
}

/// Model representing a single notification item.
class NotificationItem {
  final String id;
  final String content;
  final String? username;
  final String? linkUsername;
  final String? submissionId;
  final String? journalId;
  final String? url;
  String? avatarUrl;
  final String date; // e.g. "3 weeks ago"
  final String fullDate; // e.g. "Feb 16, 2025 05:34 PM"
  bool isChecked;

  NotificationItem({
    required this.id,
    required this.content,
    this.username,
    this.linkUsername,
    this.submissionId,
    this.journalId,
    this.url,
    this.avatarUrl,
    required this.date,
    required this.fullDate,
    this.isChecked = false,
  });


}

/// Model representing a notification section.
class NotificationSection {
  final String title;
  final String formAction;
  List<NotificationItem> items;

  NotificationSection({
    required this.title,
    required this.formAction,
    required this.items,
  });
}

/// Centralized service for notifications.
class FANotificationService with ChangeNotifier {
  final Dio _dio = Dio();
  final SfwModePreference _sfwModePreference = SfwModePreference();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock),
  );

  bool isLoading = true;
  bool hasFetched = false;
  String? errorMessage;
  List<NotificationSection> sections = [];
  String? currentUsername;
  String? linkUsername;
  String? currentUsernameFromLink;

  // For shouts caching and concurrency control.
  static final SimpleSemaphore _semaphore = SimpleSemaphore(3);
  static final Map<String, String> _avatarCache = {};
  static final Map<String, String> _previewCache = {};
  static final Map<String, Future<String?>> _previewInFlight = {};
  static bool _didFetchProfileShouts = false;
  static List<Shout> _profileShoutList = [];
  String? displayName;
  String? username;
  bool shoutsEnriched = false;
  String _shoutsLightSignature = '';
  String? _shoutsEnrichedSignature;
  String get shoutsLightSignature => _shoutsLightSignature;
  String? get shoutsEnrichedSignature => _shoutsEnrichedSignature;

  bool get shoutsNeedEnrich {
    final idx = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return false;
    if (_shoutsAppearEnrichedFromMsgOthers()) return false; // classic already has bodies/avatars
    if (_shoutsLightSignature.isEmpty) return false;
    return _shoutsEnrichedSignature != _shoutsLightSignature;
  }

  String _computeShoutsSignatureFromSections(List<NotificationSection> secs) {
    final idx = secs.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return '';
    final ids = secs[idx]
        .items
        .map((it) => it.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return ids.join(',');
  }

  Map<String, NotificationItem> _captureShoutsById() {
    final idx = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return <String, NotificationItem>{};
    final map = <String, NotificationItem>{};
    for (final it in sections[idx].items) {
      map[it.id] = it;
    }
    return map;
  }

  void _applyEnrichedShoutsFromPrevious(Map<String, NotificationItem> prevById) {
    final idx = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return;

    final existing = sections[idx].items;
    final rebuilt = <NotificationItem>[];
    for (final it in existing) {
      final prev = prevById[it.id];
      final mergedContent = (prev != null && prev.content.isNotEmpty) ? prev.content : it.content;
      final mergedUsername = (prev != null && (prev.username ?? '').isNotEmpty) ? prev.username : it.username;
      final mergedLinkUsername =
          (prev != null && (prev.linkUsername ?? '').isNotEmpty) ? prev.linkUsername : it.linkUsername;
      final mergedAvatarUrl =
          (prev != null && (prev.avatarUrl ?? '').isNotEmpty) ? prev.avatarUrl : it.avatarUrl;

      rebuilt.add(NotificationItem(
        id: it.id,
        content: mergedContent,
        username: mergedUsername,
        linkUsername: mergedLinkUsername,
        submissionId: it.submissionId,
        journalId: it.journalId,
        url: it.url,
        avatarUrl: mergedAvatarUrl,
        date: it.date,
        fullDate: it.fullDate,
        isChecked: it.isChecked,
      ));
    }
    sections[idx].items = rebuilt;
  }
  FANotificationService() {
    _initializeDio();
    fetchNotifications();
  }

  /// Stores counts from the message-bar (e.g., {"W": 1, "F": 2, "J": 3}).
  Map<String, int> messageBarCounts = {};
  NotificationCounts latestCounts = NotificationCounts(
    submissions: 0,
    watches: 0,
    comments: 0,
    favorites: 0,
    journals: 0,
    notes: 0,
  );
  Notifications latestTopBarNotifications = Notifications(
    submissions: '0',
    watches: '0',
    journals: '0',
    notes: '0',
    comments: '0',
    favorites: '0',
    registeredUsersOnline: '0',
  );

  static int _extractAnyInt(String s) {
    final m = RegExp(r'\d{1,3}(?:[,.]\d{3})*|\d+').firstMatch(s);
    if (m == null) return 0;
    return int.tryParse(m.group(0)!.replaceAll(RegExp(r'[,.]'), '')) ?? 0;
  }

  static String? _typeKeyFromHrefOrTitle({
    required String href,
    required String title,
  }) {
    final h = href.toLowerCase();
    final t = title.toLowerCase();
    if (h.contains('#submissions') || h.contains('msg/submissions') || t.contains('submission')) return 'S';
    if (h.contains('#watches') || t.contains('watch')) return 'W';
    if (h.contains('#comments') || t.contains('comment')) return 'C';
    if (h.contains('#favorites') || t.contains('favorite')) return 'F';
    if (h.contains('#journals') || t.contains('journal')) return 'J';
    if (h.contains('#notes') || h.contains('msg/pms') || t.contains('note')) return 'N';
    return null;
  }


  /// Helper method to extract a username (nicknameLink).
  static String _extractNicknameLink(dom.Element li) {
    String nicknameLink = "";

    dom.Element? parentAnchor = li.querySelector(
        'span.c-usernameBlockSimple.username-underlined a[href^="/user/"]'
    );

    if (parentAnchor == null) {
      parentAnchor = li.querySelector('a[href^="/user/"]');
    }
    if (parentAnchor != null) {
      String? href = parentAnchor.attributes['href'];
      if (href != null) {
        final regExp = RegExp(r'^/user/([^/]+)/?$');
        final match = regExp.firstMatch(href);
        if (match != null) {
          nicknameLink = match.group(1)!;
        }
      }
    }
    return nicknameLink;
  }


  Future<void> _initializeDio() async {
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.headers['Accept'] =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';
    _dio.options.headers['Accept-Encoding'] = 'gzip, deflate, br, zstd';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9,ru;q=0.8';
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) =>
    status != null && (status >= 200 && status < 400);
  }


  void clearAllNotifications() {
    isLoading = false;
    hasFetched = true;
    errorMessage = null;
    sections.clear();
    notifyListeners();
  }


  /// Fetch and parse notifications from /msg/others/.
  Future<void> fetchNotifications() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found.');
      }


      final response = await _dio.get(
        'https://www.furaffinity.net/msg/others/',
        options: Options(
          headers: {
            'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
              'a=$cookieA; b=$cookieB',
            ),
            'Referer': 'https://www.furaffinity.net/msg/others/',
          },
        ),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to load notifications.');
      }

      final document = html_parser.parse(response.data.toString());

      // Find message-bar in both modern and classic formats
      final messageBar = document.querySelector('li.message-bar-desktop') ??
          document.querySelector('li.noblock');
      messageBarCounts.clear();
      if (messageBar != null) {
        final links = messageBar.querySelectorAll('a.notification-container');
        for (final link in links) {
          final href = link.attributes['href'] ?? '';
          final text = link.text.trim();
          final title = (link.attributes['title'] ?? '').trim();
          final typeKey = _typeKeyFromHrefOrTitle(href: href, title: title);
          if (typeKey == null) continue;
          final int count = _extractAnyInt(title.isNotEmpty ? title : text);
          if (count > 0) {
            messageBarCounts[typeKey] = count;
          }
        }
      }

      final body = document.querySelector('body');
      final bool isClassic = (body?.attributes['data-static-path'] == '/themes/classic');
      int registeredUsersOnline = 0;
      if (isClassic) {
        final center = document.querySelector('div.footer center');
        final txt = center?.text ?? '';
        final m = RegExp(r'(\d+)\s+registered', caseSensitive: false).firstMatch(txt);
        if (m != null) {
          registeredUsersOnline = int.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
        }
      } else {
        final statsDiv = document.querySelector('div.online-stats');
        final txt = statsDiv?.text ?? '';
        final m = RegExp(r'(\d+)\s+registered', caseSensitive: false).firstMatch(txt);
        if (m != null) {
          registeredUsersOnline = int.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
        }
      }

      final int s = messageBarCounts['S'] ?? 0;
      final int w = messageBarCounts['W'] ?? 0;
      final int c = messageBarCounts['C'] ?? 0;
      final int f = messageBarCounts['F'] ?? 0;
      final int j = messageBarCounts['J'] ?? 0;
      final int n = messageBarCounts['N'] ?? 0;
      latestCounts = NotificationCounts(
        submissions: s,
        watches: w,
        comments: c,
        favorites: f,
        journals: j,
        notes: n,
      );
      latestTopBarNotifications = Notifications(
        submissions: '$s',
        watches: '$w',
        journals: '$j',
        notes: '$n',
        comments: '$c',
        favorites: '$f',
        registeredUsersOnline: '$registeredUsersOnline',
      );

      // We already have /msg/others/ HTML, so don't refetch it just to find the user.
      currentUsername = _extractMenubarUsernameFromDocument(document);
      currentUsernameFromLink = currentUsername;


      List<dom.Element> containers = document.querySelectorAll('section.section_container');
      if (containers.isEmpty) {
        containers = document.querySelectorAll('fieldset');
      }


      final formAction =
          document.querySelector('form#messages-form')?.attributes['action'] ?? '/msg/others/';

      List<NotificationSection> fetchedSections = [];
      for (var container in containers) {
        // Example headings: "New Watches", "New Shouts", etc.
        String heading =
            (container.querySelector('h2') ?? container.querySelector('h3'))?.text.trim() ?? 'No Title';
        heading = heading.replaceFirst(RegExp(r'^New\s+', caseSensitive: false), '');
        if (heading.isNotEmpty) {
          // Capitalize each word of the heading
          heading = heading
              .split(' ')
              .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
              .join(' ');
        }

        // Grab <li> items and ignore <li class="section-controls">
        final liItems = container
            .querySelectorAll('ul.message-stream > li')
            .where((li) => !li.classes.contains('section-controls'))
            .toList();

        List<NotificationItem> items = [];
        for (var li in liItems) {
          dom.Element? checkbox = li.querySelector('input[type="checkbox"]');
          String id = checkbox?.attributes['value'] ?? '';

          // Extract date info
          String date = '';
          String fullDate = '';
          dom.Element? dateElm = li.querySelector('.popup_date');
          if (dateElm != null) {
            date = dateElm.text.trim();
            fullDate = dateElm.attributes['title'] ?? date;
            dateElm.remove();
          }


          String content = li.innerHtml.trim().replaceAll(RegExp(r'<input[^>]*>'), '').trim();

          String? username;
          String? submissionId;
          String? journalId;
          String? url;
          String? avatarUrl;
          final lowerHeading = heading.toLowerCase();



          if (lowerHeading.contains('watches')) {
            bool isClassic = document.querySelector('body')?.attributes['data-static-path'] == '/themes/classic';
            if (isClassic) {
              dom.Element? tableElem = li.querySelector('table');
              if (tableElem != null) {
                dom.Element? av = tableElem.querySelector('td.avatar a img.avatar');

                dom.Element? avatarLink = li.querySelector('td.avatar a');
                if (avatarLink != null) {
                  String? href = avatarLink.attributes['href'];
                  if (href != null) {
                    final match = RegExp(r'/user/([^/]+)/').firstMatch(href);
                    if (match != null) {
                      linkUsername = match.group(1);
                    }
                  }
                }
                if (av != null) {
                  avatarUrl = av.attributes['src'];
                  if (avatarUrl != null && avatarUrl.startsWith('//')) {
                    avatarUrl = 'https:$avatarUrl';
                  }
                }
              }
              dom.Element? infoDiv = li.querySelector('div.info');
              if (infoDiv != null) {
                displayName = infoDiv.querySelector('span')?.text.trim();
              }


              dom.Element? avatarLink = li.querySelector('td.avatar a');
              if (avatarLink != null) {
                String? href = avatarLink.attributes['href'];
                if (href != null) {
                  final match = RegExp(r'/user/([^/]+)/').firstMatch(href);
                  if (match != null) {
                    username = match.group(1);
                  }
                }
              }

              String avatarHtml = li.querySelector('div.avatar')?.outerHtml ?? '';
              String infoHtml = li.querySelector('div.info')?.outerHtml ?? '';
              content = avatarHtml + infoHtml;
            } else {
              dom.Element? infoDiv = li.querySelector('div.info');
              if (infoDiv != null) {

                dom.Element? avatarLink = li.querySelector('div.avatar a');
                if (avatarLink != null) {
                  String? href = avatarLink.attributes['href'];
                  if (href != null) {
                    final match = RegExp(r'/user/([^/]+)/').firstMatch(href);
                    if (match != null) {
                      linkUsername = match.group(1);
                    }
                  }
                }
                displayName = infoDiv.querySelector('span')?.text.trim();
                dom.Element? avatarImg = li.querySelector('div.avatar img.avatar');
                if (avatarImg != null) {
                  avatarUrl = avatarImg.attributes['src'];
                  if (avatarUrl != null && avatarUrl.startsWith('//')) {
                    avatarUrl = 'https:$avatarUrl';
                  }
                }
                content = infoDiv.outerHtml;
              }
            }
          } else if (lowerHeading.contains('favorites')) {
            dom.Element? subLink = li.querySelector('a[href*="/view/"]');
            if (subLink != null) {
              url = subLink.attributes['href'];
              RegExp viewReg = RegExp(r'^/view/(\d+)/.*$');
              RegExpMatch? match = viewReg.firstMatch(url ?? '');
              if (match != null) {
                submissionId = match.group(1);
              }
              content = content.replaceAll('"', '');
            }
          } else if (lowerHeading.contains('journal comments')) {
            dom.Element? journLink = li.querySelector('a[href*="/journal/"]');
            if (journLink != null) {
              url = journLink.attributes['href'];
              RegExp journalReg = RegExp(r'^/journal/(\d+)/.*$');
              RegExpMatch? match = journalReg.firstMatch(url ?? '');
              if (match != null) {
                journalId = match.group(1);
              }
            }
            if (username != null && journalId != null) {
              content = "$username replied to your journal $journalId";
            } else {
              content = content
                  .replaceFirst(RegExp(r'\s*has replied to your journal titled\s*'), ' replied to your journal ')
                  .replaceAll('"', '');
            }
            if (content.isNotEmpty) {
              content = content.substring(0, content.length - 1);
            }
          } else if (lowerHeading.contains('submission comments')) {
            dom.Element? subLink = li.querySelector('a[href*="/view/"]');
            if (subLink != null) {
              url = subLink.attributes['href'];
              RegExp viewReg = RegExp(r'^/view/(\d+)/.*$');
              RegExpMatch? match = viewReg.firstMatch(url ?? '');
              if (match != null) {
                submissionId = match.group(1);
              }
              content = content.replaceAll('"', '');
            }
            if (content.isNotEmpty) {
              content = content.substring(0, content.length - 1);
            }
          }
          else if (lowerHeading.contains('shouts')) {
            bool isClassic = document.querySelector('body')?.attributes['data-static-path'] == '/themes/classic';
            String nicknameLink = "";
            if (isClassic) {
              if (li.localName == 'table' && li.id.startsWith('shout-')) {
                if (li.text.trim() == 'Shout has been removed from your page.') {
                  content = 'Shout has been removed from your page.';
                } else {
                  dom.Element? av = li.querySelector('td.alt1 a img.avatar');
                  if (av != null) {
                    avatarUrl = av.attributes['src'];
                    if (avatarUrl != null && avatarUrl.startsWith('//')) {
                      avatarUrl = 'https:$avatarUrl';
                    }
                  }
                  dom.Element? unameLink = li.querySelector('div.c-usernameBlock a.c-usernameBlock__displayName');
                  if (unameLink != null) {
                    username = unameLink.text.trim();
                    url = unameLink.attributes['href'];
                    if (url != null) {
                      final regExp = RegExp(r'^/user/([^/]+)/?$');
                      final match = regExp.firstMatch(url);
                      if (match != null) {
                        nicknameLink = match.group(1)!;
                      }
                    }
                  }
                  dom.Element? dateElem = li.querySelector('span.popup_date');
                  if (dateElem != null) {
                    date = dateElem.text.trim();
                    fullDate = dateElem.attributes['title'] ?? date;
                    dateElem.remove();
                  }
                  dom.Element? contentDiv = li.querySelector('td.alt1.addpad div.no_overflow');
                  if (contentDiv != null) {
                    content = contentDiv.text.trim();
                  } else {
                    content = li.text.trim();
                  }
                }
              } else if (li.querySelector('input[type="checkbox"][name="shouts[]"]') != null) {
                dom.Element? userLink = li.querySelector('a[href^="/user/"]');
                if (userLink != null) {
                  username = userLink.text.trim();
                  url = userLink.attributes['href'];
                  nicknameLink = _extractNicknameLink(li);
                }
                dom.Element? dateElem = li.querySelector('span.popup_date');
                if (dateElem != null) {
                  date = dateElem.text.trim();
                  fullDate = dateElem.attributes['title'] ?? date;
                  dateElem.remove();
                }
                content = li.text.trim();
              } else {
                if (li.text.contains('Shout has been removed')) {
                  content = 'Shout has been removed from your page.';
                } else {
                  dom.Element? userLink = li.querySelector('a[href^="/user/"]');
                  if (userLink != null) {
                    username = userLink.text.trim();
                    url = userLink.attributes['href'];
                    nicknameLink = _extractNicknameLink(li);
                  }
                  dom.Element? av = li.querySelector('div.avatar img.avatar');
                  if (av != null) {
                    avatarUrl = av.attributes['src'];
                    if (avatarUrl != null && avatarUrl.startsWith('//')) {
                      avatarUrl = 'https:$avatarUrl';
                    }
                  }
                }
              }
            } else {

              dom.Element? nameSpan = li.querySelector(
                  'span.c-usernameBlockSimple.username-underlined a[href^="/user/"] span.c-usernameBlockSimple__displayName'
              );
              if (nameSpan != null) {
                username = nameSpan.text.trim();
              }
              dom.Element? parentAnchor = li.querySelector(
                  'span.c-usernameBlockSimple.username-underlined a[href^="/user/"]'
              );
              if (parentAnchor != null) {
                url = parentAnchor.attributes['href'];
                String extracted = _extractNicknameLink(li);
                if (extracted.isNotEmpty) {
                  username = username ?? "";

                }
                String nicknameLinkTemp = _extractNicknameLink(li);
                if (nicknameLinkTemp.isNotEmpty) {

                }
              }
              dom.Element? avatarImg = li.querySelector('div.avatar img.avatar');
              if (avatarImg != null) {
                avatarUrl = avatarImg.attributes['src'];
                if (avatarUrl != null && avatarUrl.startsWith('//')) {
                  avatarUrl = 'https:$avatarUrl';
                }
              }
              dom.Element? timeSpan = li.querySelector('div.floatright span.popup_date');
              if (timeSpan != null) {
                date = timeSpan.text.trim();
                fullDate = timeSpan.attributes['title'] ?? date;
                timeSpan.remove();
              }
              final lower = li.text.toLowerCase();
              content = lower.contains('shout has been removed')
                  ? 'Shout has been removed from your page.'
                  : '';
            }

            String finalNicknameLink = _extractNicknameLink(li);


            items.add(NotificationItem(
              id: id,
              content: content,
              username: username,
              // For shouts, store the user slug here (used for opening profile).
              linkUsername: finalNicknameLink,
              submissionId: submissionId,
              journalId: journalId,
              url: url,
              avatarUrl: avatarUrl,
              date: date,
              fullDate: fullDate,
            ));

            continue;
          }

          else if (lowerHeading.contains('journals')) {
            dom.Element? journLink = li.querySelector('a[href*="/journal/"]');
            if (journLink != null) {
              url = journLink.attributes['href'];
              RegExp journalReg = RegExp(r'^/journal/(\d+)/.*$');
              RegExpMatch? match = journalReg.firstMatch(url ?? '');
              if (match != null) {
                journalId = match.group(1);
              }
            }
            content = content.trim();
            content = content.replaceAll('"', '').trim();
            content = content.replaceFirst(RegExp(r',\s*posted by'), ' posted by');
            if (content.endsWith(',')) {
              content = content.substring(0, content.length - 1).trim();
            }
          }


          items.add(
            NotificationItem(
              id: id,
              content: content,
              username: username,
              linkUsername: linkUsername,
              submissionId: submissionId,
              journalId: journalId,
              url: url,
              avatarUrl: avatarUrl,
              date: date,
              fullDate: fullDate,
            ),
          );
        }


        fetchedSections.add(
          NotificationSection(
            title: heading,
            formAction: formAction,
            items: items,
          ),
        );
      }


      final prevEnrichedSig = _shoutsEnrichedSignature;
      final prevById = (prevEnrichedSig != null) ? _captureShoutsById() : <String, NotificationItem>{};

      sections = fetchedSections;
      debugPrint("[fetchNotifications] Parsed sections: "
          "${sections.map((s) => s.title).toList()}");
      // Shouts signature is used to decide if we need enrichment when the user opens the tab.
      final newSig = _computeShoutsSignatureFromSections(sections);
      _shoutsLightSignature = newSig;

      // If we already enriched these exact shout IDs before, preserve the enriched data
      // across background refreshes without re-fetching.
      if (newSig.isNotEmpty && prevEnrichedSig != null && prevEnrichedSig == newSig && prevById.isNotEmpty) {
        _applyEnrichedShoutsFromPrevious(prevById);
        shoutsEnriched = true;
        _shoutsEnrichedSignature = newSig;
      } else if (newSig.isNotEmpty && _shoutsAppearEnrichedFromMsgOthers()) {
        // Classic msg/others already includes shout bodies/avatars.
        shoutsEnriched = true;
        _shoutsEnrichedSignature = newSig;
      } else {
        shoutsEnriched = false;
      }


    } catch (e, st) {

      errorMessage = e.toString();
      debugPrint("[fetchNotifications] Error: $e\n$st");
    } finally {


      isLoading = false;
      hasFetched = true;
      notifyListeners();
    }
  }


  /// Fetch shouts from the user's profile.
  static Future<List<Shout>> fetchProfileShouts(String myUsername, {bool forceRefresh = false}) async {
    if (_didFetchProfileShouts && !forceRefresh) {
      debugPrint("[fetchProfileShouts] Using cached _profileShoutList (size=${_profileShoutList.length})");
      return _profileShoutList;
    }
    _didFetchProfileShouts = true;
    _profileShoutList.clear();
    final url = 'https://www.furaffinity.net/user/$myUsername/';
    debugPrint("[fetchProfileShouts] Fetching $url ...");
    await _semaphore.acquire();
    try {
      String? cookieHeader = await _getCookieHeader();
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': FAHttp.userAgent,
          if (cookieHeader != null) 'Cookie': cookieHeader,
        },
      );

      if (resp.statusCode == 200) {
        final doc = html_parser.parse(resp.body);
        bool isClassic = doc.querySelector('body')?.attributes['data-static-path'] == '/themes/classic';
        if (isClassic) {
          final shoutTables = doc.querySelectorAll('table[id^="shout-"]');
          debugPrint("[fetchProfileShouts] Found ${shoutTables.length} classic shout table(s)");
          for (var t in shoutTables) {
            String nickname = "";
            String nicknameLink = "";
            String postedTitle = "";
            String postedAgo = "";
            String textContent = "";
            String avatarUrl = "";
            dom.Element? avatarImg = t.querySelector('td.alt1 a img.avatar');
            if (avatarImg != null) {
              avatarUrl = avatarImg.attributes['src'] ?? "";
              if (avatarUrl.startsWith('//')) avatarUrl = 'https:' + avatarUrl;
            }
            dom.Element? unameLink = t.querySelector('div.c-usernameBlock a.c-usernameBlock__displayName');
            if (unameLink != null) {
              nickname = unameLink.text.trim();
              String? href = unameLink.attributes['href'];
              if (href != null) {
                final regExp = RegExp(r'^/user/([^/]+)/?$');
                final match = regExp.firstMatch(href);
                if (match != null) {
                  nicknameLink = match.group(1)!;
                }
              }
            }
            dom.Element? dateElem = t.querySelector('span.popup_date');
            if (dateElem != null) {
              postedAgo = dateElem.text.trim();
              postedTitle = dateElem.attributes['title']?.replaceFirst(RegExp(r'^on\s+'), '').trim() ?? "";
            }
            dom.Element? contentDiv = t.querySelector('td.alt1.addpad div.no_overflow');
            if (contentDiv != null) {
              textContent = contentDiv.innerHtml.trim();
            }
            _profileShoutList.add(Shout(
              id: '',
              nickname: nickname,
              nicknameLink: nicknameLink,
              postedTitle: postedTitle,
              avatarUrl: avatarUrl,
              postedAgo: postedAgo,
              textContent: textContent,
              isRemoved: false,
            ));
          }
        } else {
          final containers = doc.querySelectorAll('div.comment_container');
          debugPrint("[fetchProfileShouts] Found ${containers.length} modern comment_container blocks");
          for (var c in containers) {
            String nickname = "";
            String nicknameLink = _extractNicknameLink(c);
            String postedTitle = "";
            String postedAgo = "";
            String textContent = "";
            String avatarUrl = "";
            dom.Element? disp = c.querySelector('.c-usernameBlock__displayName .js-displayName');
            if (disp != null) {
              nickname = disp.text.trim();
            }
            dom.Element? dateSpan = c.querySelector('comment-date span.popup_date');
            if (dateSpan != null) {
              postedAgo = dateSpan.text.trim();
              postedTitle = dateSpan.attributes['title']?.replaceFirst(RegExp(r'^on\s+'), '').trim() ?? "";
            }
            dom.Element? textElem = c.querySelector('comment-user-text.comment_text');
            if (textElem != null) {
              textContent = textElem.text.trim();
            }
            dom.Element? avatarDiv = c.querySelector('div.avatar');
            if (avatarDiv != null) {
              dom.Element? link = avatarDiv.querySelector('a[href^="/user/"]');
              if (link != null) {
                dom.Element? img = link.querySelector('img.comment_useravatar');
                if (img != null) {
                  var src = img.attributes['src'] ?? "";
                  if (src.startsWith('//')) src = 'https:' + src;
                  avatarUrl = src;
                }
              }
            }
            _profileShoutList.add(Shout(
              id: '',
              nickname: nickname,
              nicknameLink: nicknameLink,
              postedTitle: postedTitle,
              avatarUrl: avatarUrl,
              postedAgo: postedAgo,
              textContent: textContent,
              isRemoved: false,
            ));
          }
        }
      }
    } catch (e, st) {
      debugPrint("[fetchProfileShouts] Error: $e\n$st");
    } finally {
      _semaphore.release();
    }
    debugPrint("[fetchProfileShouts] Returning ${_profileShoutList.length} items");
    return _profileShoutList;
  }

  /// Merge shouts from /msg/others/ and the profile page.
  static Future<List<Shout>> fetchMsgCenterShouts() async {
    debugPrint("[fetchMsgCenterShouts] Called");
    final url = 'https://www.furaffinity.net/msg/others/';
    try {
      String? cookieHeader = await _getCookieHeader();
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': FAHttp.userAgent,
          if (cookieHeader != null) 'Cookie': cookieHeader,
        },
      );
      if (resp.statusCode != 200) return <Shout>[];
      final doc = html_parser.parse(resp.body);
      return await _fetchMsgCenterShoutsFromDocument(doc);
    } catch (e, st) {
      debugPrint("[fetchMsgCenterShouts] Error: $e\n$st");
      return <Shout>[];
    }
  }

  static String _extractMenubarUsernameFromDocument(dom.Document doc) {
    final body = doc.querySelector('body');
    final bool isClassic = (body?.attributes['data-static-path'] == '/themes/classic');

    // Classic (and sometimes modern) provides #my-username.
    final myUsernameElem = doc.getElementById("my-username");
    if (myUsernameElem != null) {
      final href = myUsernameElem.attributes['href'];
      if (href != null) {
        final match = RegExp(r'^/user/([^/]+)/?$').firstMatch(href);
        if (match != null) return match.group(1)!;
      }
    }

    if (!isClassic) {
      // Modern menubar user link.
      final menubarLink =
          doc.querySelector('div.floatleft.hideonmobile a[href^="/user/"]');
      final href = menubarLink?.attributes['href'];
      if (href != null) {
        final match = RegExp(r'^/user/([^/]+)/?$').firstMatch(href);
        if (match != null) return match.group(1)!;
      }
    }

    return "";
  }

  static List<Map<String, dynamic>> _parseMsgOthersShoutsFromDocument(dom.Document doc) {
    final results = <Map<String, dynamic>>[];
    final bool isClassic =
        doc.querySelector('body')?.attributes['data-static-path'] == '/themes/classic';

    if (isClassic) {
      final liItems = doc
          .querySelectorAll('li')
          .where((li) => li.querySelector('input[type="checkbox"][name="shouts[]"]') != null)
          .toList();
      debugPrint("[fetchMsgOthersShouts] Found ${liItems.length} classic shout <li> items");
      for (final li in liItems) {
        final checkbox = li.querySelector('input[type="checkbox"][name="shouts[]"]');
        final id = checkbox?.attributes['value'] ?? '';
        final isRemoved = li.text.toLowerCase().contains('shout has been removed');
        String nickname = "";
        String nicknameLink = "";
        if (!isRemoved) {
          final nameSpan = li.querySelector(
              'span.c-usernameBlockSimple.username-underlined a span.c-usernameBlockSimple__displayName');
          if (nameSpan != null) nickname = nameSpan.text.trim();
          nicknameLink = _extractNicknameLink(li);
        }
        String postedAgo = "";
        String postedTitle = "";
        final timeSpan = li.querySelector('span.popup_date');
        if (timeSpan != null) {
          postedAgo = timeSpan.text.trim();
          postedTitle = (timeSpan.attributes['title'] ?? postedAgo)
              .replaceFirst(RegExp(r'^on\s+'), '')
              .trim();
        }
        results.add({
          "id": id,
          "nickname": nickname,
          "nicknameLink": nicknameLink,
          "postedTitle": postedTitle,
          "postedAgo": postedAgo,
          "isRemoved": isRemoved,
        });
      }

      final tableShouts = doc.querySelectorAll('table[id^="shout-"]');
      debugPrint("[fetchMsgOthersShouts] Found ${tableShouts.length} classic shout <table> items");
      for (final t in tableShouts) {
        final shoutId = t.id.replaceFirst('shout-', '');
        final isRemoved = t.text.toLowerCase().contains('shout has been removed');

        String nickname = "";
        String nicknameLink = "";
        final nameElem = t.querySelector('div.c-usernameBlock a.c-usernameBlock__displayName');
        if (nameElem != null) {
          nickname = nameElem.text.trim();
          final href = nameElem.attributes['href'];
          if (href != null) {
            final match = RegExp(r'^/user/([^/]+)/?$').firstMatch(href);
            if (match != null) nicknameLink = match.group(1)!;
          }
        }

        String postedAgo = "";
        String postedTitle = "";
        final dateElem = t.querySelector('span.popup_date');
        if (dateElem != null) {
          postedAgo = dateElem.text.trim();
          postedTitle = (dateElem.attributes['title'] ?? postedAgo)
              .replaceFirst(RegExp(r'^on\s+'), '')
              .trim();
        }

        String textHtml = "";
        final contentDiv = t.querySelector('td.alt1.addpad div.no_overflow');
        if (contentDiv != null) {
          textHtml = contentDiv.innerHtml.trim();
          textHtml = textHtml.replaceAllMapped(
            RegExp(r'<i\s+class="smilie\s+([\w-]+)"[^>]*></i>'),
                (m) => '[smilie-${m.group(1)}]',
          );
        }

        String avatarUrl = "";
        final avatarImg = t.querySelector('td.alt1 a img.avatar');
        if (avatarImg != null) {
          avatarUrl = avatarImg.attributes['src'] ?? "";
          if (avatarUrl.startsWith('//')) avatarUrl = 'https:' + avatarUrl;
        }

        results.add({
          "id": shoutId,
          "nickname": nickname,
          "nicknameLink": nicknameLink,
          "postedTitle": postedTitle,
          "postedAgo": postedAgo,
          "isRemoved": isRemoved,
          "avatarUrl": avatarUrl,
          "textHtml": textHtml,
        });
      }
    } else {
      final shoutSection = doc.querySelector('section#messages-shouts');
      if (shoutSection == null) {
        debugPrint("[fetchMsgOthersShouts] No #messages-shouts section found.");
        return results;
      }
      final ul = shoutSection.querySelector('ul.message-stream');
      if (ul == null) {
        debugPrint("[fetchMsgOthersShouts] No .message-stream found in #messages-shouts");
        return results;
      }
      final liItems = ul.querySelectorAll('li');
      debugPrint("[fetchMsgOthersShouts] Found ${liItems.length} <li> items");
      for (final li in liItems) {
        final checkbox = li.querySelector('input[type="checkbox"][name="shouts[]"]');
        final id = checkbox?.attributes['value'] ?? '';
        final isRemoved = li.text.toLowerCase().contains('shout has been removed');
        String nickname = "";
        String nicknameLink = "";
        if (!isRemoved) {
          final nameSpan = li.querySelector(
              'span.c-usernameBlockSimple.username-underlined a[href^="/user/"] span.c-usernameBlockSimple__displayName');
          if (nameSpan != null) nickname = nameSpan.text.trim();
          nicknameLink = _extractNicknameLink(li);
        }
        String postedAgo = "";
        String postedTitle = "";
        final timeSpan = li.querySelector('div.floatright span.popup_date');
        if (timeSpan != null) {
          postedAgo = timeSpan.text.trim();
          postedTitle = (timeSpan.attributes['title'] ?? postedAgo)
              .replaceFirst(RegExp(r'^on\s+'), '')
              .trim();
        }
        results.add({
          "id": id,
          "nickname": nickname,
          "nicknameLink": nicknameLink,
          "postedTitle": postedTitle,
          "postedAgo": postedAgo,
          "isRemoved": isRemoved,
        });
      }
    }
    debugPrint("[fetchMsgOthersShouts] Returning ${results.length} items");
    return results;
  }

  static List<Shout> _mergeMsgShoutsWithProfile({
    required List<Map<String, dynamic>> msgItems,
    required List<Shout> profileShouts,
  }) {
    final results = <Shout>[];
    for (final m in msgItems) {
      final id = (m["id"] as String? ?? '').trim();
      final isRemoved = m["isRemoved"] as bool? ?? false;
      final postedTitle = (m["postedTitle"] as String? ?? "").trim();
      final postedAgo = (m["postedAgo"] as String? ?? "").trim();
      final nick = (m["nickname"] as String? ?? "").trim();
      final nicknameLink = (m["nicknameLink"] as String? ?? "").trim();

      if (isRemoved) {
        results.add(Shout(
          id: id,
          nickname: nick,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: "",
          postedAgo: postedAgo,
          textContent: "Shout has been removed from your page.",
          isRemoved: true,
        ));
        continue;
      }

      // If msg/others already provided full details (classic), prefer those.
      final msgAvatarUrl = (m["avatarUrl"] as String? ?? "").trim();
      final msgTextHtml = (m["textHtml"] as String? ?? "").trim();
      if (msgAvatarUrl.isNotEmpty || msgTextHtml.isNotEmpty) {
        results.add(Shout(
          id: id,
          nickname: nick,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: msgAvatarUrl,
          postedAgo: postedAgo,
          textContent: msgTextHtml.isNotEmpty ? msgTextHtml : "left a shout:",
          isRemoved: false,
        ));
        continue;
      }

      // Otherwise, merge with profile shouts for avatar/text if possible.
      final matches = profileShouts.where((p) {
        final nicknameMatches = p.nickname.trim().toLowerCase() == nick.trim().toLowerCase();
        final timeMatches = p.postedTitle == postedTitle;
        return nicknameMatches && timeMatches;
      }).toList();

      if (matches.isNotEmpty) {
        final profileShout = matches.first;
        results.add(Shout(
          id: id,
          nickname: nick,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: profileShout.avatarUrl,
          postedAgo: postedAgo,
          textContent: profileShout.textContent,
          isRemoved: false,
        ));
      } else {
        results.add(Shout(
          id: id,
          nickname: nick,
          nicknameLink: nicknameLink,
          postedTitle: postedTitle,
          avatarUrl: "",
          postedAgo: postedAgo,
          textContent: "",
          isRemoved: false,
        ));
      }
    }
    debugPrint("[fetchMsgCenterShouts] Final results count: ${results.length}");
    return results;
  }

  static Future<List<Shout>> _fetchMsgCenterShoutsFromDocument(dom.Document doc) async {
    final msgItems = _parseMsgOthersShoutsFromDocument(doc);
    debugPrint("[fetchMsgCenterShouts] msgItems count=${msgItems.length}");

    final myUsername = _extractMenubarUsernameFromDocument(doc);
    if (myUsername.isEmpty) {
      debugPrint("[fetchMsgCenterShouts] No user found in menubar; profile parse skipped.");
      return _mergeMsgShoutsWithProfile(msgItems: msgItems, profileShouts: const []);
    }

    // If msg/others already contains avatar/text for all non-removed shouts (classic),
    // don't fetch the profile page.
    final needsProfileMerge = msgItems.any((m) {
      final removed = m["isRemoved"] as bool? ?? false;
      if (removed) return false;
      final avatar = (m["avatarUrl"] as String? ?? "").trim();
      final text = (m["textHtml"] as String? ?? "").trim();
      return avatar.isEmpty && text.isEmpty;
    });
    if (!needsProfileMerge) {
      return _mergeMsgShoutsWithProfile(msgItems: msgItems, profileShouts: const []);
    }

    final profileShouts = await fetchProfileShouts(myUsername, forceRefresh: true);
    return _mergeMsgShoutsWithProfile(msgItems: msgItems, profileShouts: profileShouts);
  }

  /// Parse /msg/others/ to get shouts.
  static Future<List<Map<String, dynamic>>> fetchMsgOthersShouts() async {
    final url = 'https://www.furaffinity.net/msg/others/';
    debugPrint("[fetchMsgOthersShouts] Checking $url...");
    try {
      String? cookieHeader = await _getCookieHeader();
      final resp = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': FAHttp.userAgent,
          if (cookieHeader != null) 'Cookie': cookieHeader,
        },
      );

      if (resp.statusCode != 200) return <Map<String, dynamic>>[];
      final doc = html_parser.parse(resp.body);
      return _parseMsgOthersShoutsFromDocument(doc);
    } catch (e, st) {
      debugPrint("[fetchMsgOthersShouts] Error: $e\n$st");
    }
    // If anything fails, return empty list.
    return <Map<String, dynamic>>[];
  }

  String _normalizeDate(String s) {
    return s.replaceFirst(RegExp(r'^on\s+'), '').trim();
  }

  /// Remove selected items in a section.
  Future<void> removeSelected(int sectionIndex) async {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    List<NotificationItem> selectedItems = sections[sectionIndex].items.where((item) => item.isChecked).toList();
    if (selectedItems.isEmpty) return;
    isLoading = true;
    notifyListeners();
    try {
      String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found.');
      }
      String tLower = sections[sectionIndex].title.toLowerCase();
      Map<String, dynamic> formData = {};
      if (tLower.contains('shouts')) {
        formData['remove-shouts'] = 'Remove Selected Shouts';
        formData['shouts'] = selectedItems.map((x) => x.id).toList();
      } else if (tLower.contains('watches')) {
        formData['remove-watches'] = 'Remove Selected Watches';
        formData['watches'] = selectedItems.map((x) => x.id).toList();
      } else if (tLower.contains('submission comments')) {
        formData['remove-submission-comments'] = 'Remove Selected Comments';
        formData['comments-submissions'] = selectedItems.map((x) => x.id).toList();
      } else if (tLower.contains('journal comments')) {
        formData['remove-journal-comments'] = 'Remove Selected Comments';
        formData['comments-journals'] = selectedItems.map((x) => x.id).toList();
      } else if (tLower.contains('favorites')) {
        formData['remove-favorites'] = 'Remove Selected Favorites';
        formData['favorites'] = selectedItems.map((x) => x.id).toList();
      } else if (tLower.contains('journals')) {
        formData['remove-journals'] = 'Remove Selected Journals';
        formData['journals'] = selectedItems.map((x) => x.id).toList();
      }
      FormData dioFormData = FormData();
      formData.forEach((k, v) {
        if (v is List) {
          for (var val in v) {
            dioFormData.fields.add(MapEntry('$k[]', val));
          }
        } else {
          dioFormData.fields.add(MapEntry(k, v));
        }
      });
      final response = await _dio.post(
        'https://www.furaffinity.net${sections[sectionIndex].formAction}',
        data: dioFormData,
        options: Options(
          headers: {
            'Referer': 'https://www.furaffinity.net/msg/others/',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
              'a=$cookieA; b=$cookieB',
            ),
          },
        ),
      );
      if (tLower.contains('shouts')) {
        if (response.statusCode == 200 || response.statusCode == 302) {
          sections[sectionIndex].items.removeWhere((x) => x.isChecked);
          if (sections[sectionIndex].items.isEmpty) {
            sections.removeAt(sectionIndex);
          }
          notifyListeners();
        } else {
          throw Exception('Failed to remove selected shouts.');
        }
      } else {
        if (response.statusCode == 302) {
          sections[sectionIndex].items.removeWhere((x) => x.isChecked);
          if (sections[sectionIndex].items.isEmpty) {
            sections.removeAt(sectionIndex);
          }
          notifyListeners();
        } else {
          throw Exception('Failed to remove selected items.');
        }
      }
    } catch (e, st) {
      errorMessage = e.toString();
      debugPrint("[removeSelected] $e\n$st");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Nuke an entire section.
  Future<void> nukeSection(int sectionIndex) async {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    isLoading = true;
    notifyListeners();
    try {
      String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found.');
      }
      String tLower = sections[sectionIndex].title.toLowerCase();
      Map<String, dynamic> formData = {};
      if (tLower.contains('watches')) {
        formData['nuke-watches'] = 'Nuke Watches';
      } else if (tLower.contains('submission comments')) {
        formData['nuke-submission-comments'] = 'Nuke Submission Comments';
      } else if (tLower.contains('journal comments')) {
        formData['nuke-journal-comments'] = 'Nuke Journal Comments';
      } else if (tLower.contains('shouts')) {
        formData['nuke-shouts'] = 'Nuke Shouts';
      } else if (tLower.contains('favorites')) {
        formData['nuke-favorites'] = 'Nuke Favorites';
      } else if (tLower.contains('journals')) {
        formData['nuke-journals'] = 'Nuke Journals';
      } else {
        throw Exception('Unknown section type for nuking: ${sections[sectionIndex].title}');
      }
      FormData dioFormData = FormData();
      formData.forEach((k, v) {
        dioFormData.fields.add(MapEntry(k, v));
      });
      final response = await _dio.post(
        'https://www.furaffinity.net${sections[sectionIndex].formAction}',
        data: dioFormData,
        options: Options(
          headers: {
            'Referer': 'https://www.furaffinity.net/msg/others/',
            'Content-Type': 'multipart/form-data',
            'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
              'a=$cookieA; b=$cookieB',
            ),
          },
        ),
      );
      if (response.statusCode == 302) {
        sections[sectionIndex].items.clear();
        sections.removeAt(sectionIndex);
        notifyListeners();
      } else {
        throw Exception('Failed to nuke items.');
      }
    } catch (e, st) {
      errorMessage = e.toString();
      debugPrint("[nukeSection] $e\n$st");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }



  /// Remove all notifications in all sections.
  Future<void> removeAllNotifications() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found.');
      }
      for (int i = sections.length - 1; i >= 0; i--) {
        List<NotificationItem> items = sections[i].items;
        if (items.isEmpty) continue;
        String headingLower = sections[i].title.toLowerCase();
        Map<String, dynamic> formData = {};
        if (headingLower.contains('shouts')) {
          formData['remove-shouts'] = 'Remove Selected Shouts';
          formData['shouts'] = items.map((x) => x.id).toList();
        } else if (headingLower.contains('watches')) {
          formData['remove-watches'] = 'Remove Selected Watches';
          formData['watches'] = items.map((x) => x.id).toList();
        } else if (headingLower.contains('submission comments')) {
          formData['remove-submission-comments'] = 'Remove Selected Comments';
          formData['comments-submissions'] = items.map((x) => x.id).toList();
        } else if (headingLower.contains('journal comments')) {
          formData['remove-journal-comments'] = 'Remove Selected Comments';
          formData['comments-journals'] = items.map((x) => x.id).toList();
        } else if (headingLower.contains('favorites')) {
          formData['remove-favorites'] = 'Remove Selected Favorites';
          formData['favorites'] = items.map((x) => x.id).toList();
        } else if (headingLower.contains('journals')) {
          formData['remove-journals'] = 'Remove Selected Journals';
          formData['journals'] = items.map((x) => x.id).toList();
        } else {
          continue;
        }
        FormData dioFormData = FormData();
        formData.forEach((k, val) {
          if (val is List) {
            for (var v in val) {
              dioFormData.fields.add(MapEntry('$k[]', v));
            }
          } else {
            dioFormData.fields.add(MapEntry(k, val));
          }
        });
        final resp = await _dio.post(
          'https://www.furaffinity.net${sections[i].formAction}',
          data: dioFormData,
          options: Options(
            headers: {
              'Referer': 'https://www.furaffinity.net/msg/others/',
              'Content-Type': 'application/x-www-form-urlencoded',
              'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
                'a=$cookieA; b=$cookieB',
              ),
            },
          ),
        );
        if (resp.statusCode == 302) {
          sections[i].items.clear();
          sections.removeAt(i);
        } else {
          throw Exception('Failed to remove all from section: ${sections[i].title}');
        }
      }
    } catch (e, st) {
      errorMessage = e.toString();
      debugPrint("[removeAllNotifications] $e\n$st");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Update the shouts section with new data.
  void updateShouts(List<dynamic> newShouts) {
    int idx = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return;
    List<NotificationItem> updated = [];
    for (var sh in newShouts) {
      NotificationItem? oldItem = sections[idx].items.firstWhere(
              (o) => o.id == sh.id,
          orElse: () => NotificationItem(
            id: sh.id,
            content: sh.textContent,
            username: sh.nickname,
            linkUsername: sh.nicknameLink,
            avatarUrl: sh.avatarUrl,
            date: sh.postedAgo,
            fullDate: sh.postedTitle,
          ));
      updated.add(NotificationItem(
        id: sh.id,
        content: sh.textContent,
        username: sh.nickname,
        linkUsername: sh.nicknameLink,
        avatarUrl: sh.avatarUrl,
        date: sh.postedAgo,
        fullDate: sh.postedTitle,
        isChecked: oldItem.isChecked,
      ));
    }
    sections[idx].items = updated;
    shoutsEnriched = true;
    final sig = updated.map((it) => it.id.trim()).where((id) => id.isNotEmpty).join(',');
    _shoutsLightSignature = sig;
    _shoutsEnrichedSignature = sig;
    notifyListeners();
  }

  bool _shoutsAppearEnrichedFromMsgOthers() {
    final idx = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return false;
    final items = sections[idx].items;
    if (items.isEmpty) return false;
    // If any non-removed shout has a non-empty body, consider it enriched (classic msg/others).
    return items.any((it) {
      final removed = it.content.toLowerCase().contains('shout has been removed');
      if (removed) return false;
      return it.content.trim().isNotEmpty;
    });
  }

  static String _normalizeShoutStamp(String s) {
    return s.replaceFirst(RegExp(r'^on\s+', caseSensitive: false), '').trim();
  }

  Future<List<Shout>> enrichShoutsFromProfileIfNeeded({bool force = false}) async {
    final idx = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return const <Shout>[];
    if (!force && shoutsEnriched) {
      return sections[idx].items.map((it) {
        return Shout(
          id: it.id,
          nickname: it.username ?? '',
          nicknameLink: it.linkUsername ?? '',
          postedTitle: it.fullDate,
          avatarUrl: it.avatarUrl ?? '',
          postedAgo: it.date,
          textContent: it.content,
          isRemoved: it.content.toLowerCase().contains('shout has been removed'),
          isChecked: it.isChecked,
        );
      }).toList();
    }

    final my = (currentUsername ?? '').trim();
    if (my.isEmpty) return const <Shout>[];

    final profileShouts = await fetchProfileShouts(my, forceRefresh: true);

    // Merge by nicknameLink (preferred) + timestamp, falling back to display name.
    final currentItems = sections[idx].items;
    final enriched = <Shout>[];
    for (final item in currentItems) {
      final removed = item.content.toLowerCase().contains('shout has been removed');
      final wantLink = (item.linkUsername ?? '').trim().toLowerCase();
      final wantName = (item.username ?? '').trim().toLowerCase();
      final wantStamp = _normalizeShoutStamp(item.fullDate);

      Shout? match;
      if (!removed) {
        for (final p in profileShouts) {
          final pLink = p.nicknameLink.trim().toLowerCase();
          final pName = p.nickname.trim().toLowerCase();
          final pStamp = _normalizeShoutStamp(p.postedTitle);
          final linkOk = wantLink.isNotEmpty && pLink.isNotEmpty ? (wantLink == pLink) : true;
          final nameOk = wantName.isNotEmpty ? (pName == wantName) : true;
          if (pStamp == wantStamp && linkOk && nameOk) {
            match = p;
            break;
          }
        }
      }

      enriched.add(Shout(
        id: item.id,
        nickname: item.username ?? '',
        nicknameLink: item.linkUsername ?? '',
        postedTitle: item.fullDate,
        avatarUrl: match?.avatarUrl ?? (item.avatarUrl ?? ''),
        postedAgo: item.date,
        textContent: match?.textContent ?? item.content,
        isRemoved: removed,
        isChecked: item.isChecked,
      ));
    }

    updateShouts(enriched);
    return enriched;
  }

  /// Toggle selection of all items in a section.
  void toggleSelectAll(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    bool shouldSelectAll = sections[sectionIndex].items.any((item) => !item.isChecked);
    for (var item in sections[sectionIndex].items) {
      item.isChecked = shouldSelectAll;
    }
    notifyListeners();
  }

  /// Mark/unmark a single shout by ID.
  void setShoutCheckedById(String id, bool isChecked) {
    int idx = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return;
    for (var item in sections[idx].items) {
      if (item.id == id) {
        item.isChecked = isChecked;
        notifyListeners();
        break;
      }
    }
  }



  static Future<String?> _getCookieHeader() async {
    try {
      String? cookieA = await const FlutterSecureStorage(iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock)).read(key: 'fa_cookie_a');
      String? cookieB = await const FlutterSecureStorage(iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock)).read(key: 'fa_cookie_b');
      bool sfwEnabled = await const SfwModePreference().loadSfwEnabled();
      String cookieHeader = '';
      if (cookieA != null && cookieA.isNotEmpty) {
        cookieHeader += 'a=$cookieA; ';
      }
      if (cookieB != null && cookieB.isNotEmpty) {
        cookieHeader += 'b=$cookieB; ';
      }
      if (sfwEnabled) {
        cookieHeader += 'sfw=1;';
      }
      cookieHeader = cookieHeader.trim();
      cookieHeader = await FaCookieHelper.appendCfClearanceToCookieHeader(cookieHeader);
      debugPrint("[_getCookieHeader] $cookieHeader");
      return cookieHeader;
    } catch (e) {
      debugPrint("[_getCookieHeader] Error reading cookies: $e");
    }
    return null;
  }

  /// Fetch the user's avatar URL.
  static Future<String?> fetchAvatarUrl(String username) async {
    if (username.isEmpty) return null;
    String canonicalUsername;
    if (username.startsWith('/user/')) {
      canonicalUsername = username.replaceFirst('/user/', '').replaceAll('/', '');
    } else {
      canonicalUsername = username.toLowerCase().replaceAll('_', '');
    }
    final fullUrl = 'https://www.furaffinity.net/user/$canonicalUsername/';
    debugPrint("[fetchAvatarUrl] Checking $fullUrl");
    if (_avatarCache.containsKey(canonicalUsername)) {
      debugPrint("[fetchAvatarUrl] Cache hit for $canonicalUsername -> ${_avatarCache[canonicalUsername]}");
      return _avatarCache[canonicalUsername];
    }
    await _semaphore.acquire();
    try {
      String? cookieHeader = await _getCookieHeader();
      final response = await http.get(
        Uri.parse(fullUrl),
        headers: {
          'User-Agent': FAHttp.userAgent,
          if (cookieHeader != null) 'Cookie': cookieHeader,
        },
      );
      debugPrint("[fetchAvatarUrl] code=${response.statusCode}");
      if (response.statusCode == 200) {
        final doc = html_parser.parse(response.body);
        bool isClassic = doc.querySelector('body')?.attributes['data-static-path'] == '/themes/classic';
        dom.Element? avatarElem;
        if (isClassic) {
          avatarElem = doc.querySelector('td.alt1 a img.avatar');
        } else {
          avatarElem = doc.querySelector('userpage-nav-avatar a.current img');
        }
        if (avatarElem != null) {
          String? src = avatarElem.attributes['src'];
          if (src != null && src.isNotEmpty) {
            if (src.startsWith('//')) src = 'https:' + src;
            _avatarCache[canonicalUsername] = src;
            debugPrint("[fetchAvatarUrl] Found -> $src");
            return src;
          }
        }
      }
    } catch (e) {
      debugPrint("[fetchAvatarUrl] Error: $e");
    } finally {
      _semaphore.release();
    }
    return null;
  }

  /// Fetch the submission’s preview image URL.
  static Future<String?> fetchSubmissionPreview(String submissionId) async {
    if (submissionId.isEmpty) return null;
    if (_previewCache.containsKey(submissionId)) {
      debugPrint("[fetchSubmissionPreview] Cache hit for submission $submissionId: ${_previewCache[submissionId]}");
      return _previewCache[submissionId];
    }
    // If many rows reference the same submissionId, de-dupe in-flight requests
    // so we don't spam /view/<id>/.
    final inFlight = _previewInFlight[submissionId];
    if (inFlight != null) return inFlight;

    Future<String?> doFetch() async {
      await _semaphore.acquire();
      try {
        // Cache may have been filled while we were queued behind the semaphore.
        final cached = _previewCache[submissionId];
        if (cached != null) return cached;

        String? cookieHeader = await _getCookieHeader();
        final url = 'https://www.furaffinity.net/view/$submissionId/';
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'User-Agent': FAHttp.userAgent,
            if (cookieHeader != null) 'Cookie': cookieHeader,
          },
        );
        debugPrint("[fetchSubmissionPreview] Response code for $submissionId: ${response.statusCode}");
        if (response.statusCode == 200) {
          final document = html_parser.parse(response.body);
          dom.Element? noticeSection = document.querySelector('section.aligncenter.notice-message');
          if (noticeSection != null && noticeSection.text.contains("This submission contains Mature or Adult content")) {
            // Note: UI treats this as a "bad" URL and shows an errorWidget; that's OK.
            return "assets/images/nsfw.png";
          }
          final images = document.querySelectorAll('img');
          for (var img in images) {
            if (img.attributes.containsKey('data-preview-src')) {
              String? src = img.attributes['data-preview-src'];
              if (src != null && src.isNotEmpty) {
                if (src.startsWith('//')) src = 'https:' + src;
                _previewCache[submissionId] = src;
                return src;
              }
            }
          }
          dom.Element? fallbackElement = document.querySelector('img#submissionImg');
          if (fallbackElement != null) {
            String? fallbackSrc = fallbackElement.attributes['src'];
            if (fallbackSrc != null && fallbackSrc.isNotEmpty) {
              if (fallbackSrc.startsWith('//')) fallbackSrc = 'https:' + fallbackSrc;
              _previewCache[submissionId] = fallbackSrc;
              return fallbackSrc;
            }
          }
        }
      } catch (e) {
        debugPrint("[fetchSubmissionPreview] Error fetching preview for submission $submissionId: $e");
      } finally {
        _semaphore.release();
        _previewInFlight.remove(submissionId);
      }
      return null;
    }

    final future = doFetch();
    _previewInFlight[submissionId] = future;
    return future;
  }
}
