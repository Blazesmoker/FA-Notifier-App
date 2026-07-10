import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:FANotifier/features/notifications/domain/notifications.dart';
import 'package:FANotifier/features/notifications/domain/notification_counts.dart';
import 'package:FANotifier/features/notifications/domain/fa_notification_models.dart';
import 'package:FANotifier/features/notifications/data/simple_semaphore.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_link_parser.dart';
import 'package:FANotifier/features/notifications/data/notification_section_parser_helpers.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_cookie_header_provider.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_media_repository.dart';
import 'package:FANotifier/features/notifications/data/fa_notification_shout_repository.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';

import 'notification_shout_parser.dart';

/// Centralized service for notifications.
class FANotificationService with ChangeNotifier {
  final Dio _dio = Dio();
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

  static final SimpleSemaphore _semaphore = SimpleSemaphore(3);
  static const FaNotificationCookieHeaderProvider _cookieHeaderProvider =
      FaNotificationCookieHeaderProvider();
  static final FaNotificationShoutRepository _shoutRepository =
      FaNotificationShoutRepository(
    semaphore: _semaphore,
    cookieHeaderProvider: _cookieHeaderProvider,
  );
  static final FaNotificationMediaRepository _mediaRepository =
      FaNotificationMediaRepository(
    semaphore: _semaphore,
    cookieHeaderProvider: _cookieHeaderProvider,
  );
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
  }

  /// Stores counts from the message-bar (e.g., {"W": 1, "F": 2, "J": 3}).
  Map<String, int> messageBarCounts = {};
  bool hasValidLatestCountsSnapshot = false;
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

  void applyTopbarCounts(NotificationCounts counts) {
    hasValidLatestCountsSnapshot = true;
    latestCounts = counts;
    _setMessageBarCount('S', counts.submissions);
    _setMessageBarCount('W', counts.watches);
    _setMessageBarCount('C', counts.comments);
    _setMessageBarCount('F', counts.favorites);
    _setMessageBarCount('J', counts.journals);
    _setMessageBarCount('N', counts.notes);
    latestTopBarNotifications = Notifications(
      submissions: '${counts.submissions}',
      watches: '${counts.watches}',
      journals: '${counts.journals}',
      notes: '${counts.notes}',
      comments: '${counts.comments}',
      favorites: '${counts.favorites}',
      registeredUsersOnline: latestTopBarNotifications.registeredUsersOnline,
    );
    notifyListeners();
  }

  void _setMessageBarCount(String key, int value) {
    if (value > 0) {
      messageBarCounts[key] = value;
    } else {
      messageBarCounts.remove(key);
    }
  }

  Future<void> _initializeDio() async {
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.headers['Accept'] =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';
    _dio.options.headers['Accept-Encoding'] = 'gzip, deflate, br, zstd';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9,ru;q=0.8';
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) =>
        status != null && status >= 200 && status < 600;
  }


  void clearAllNotifications() {
    isLoading = false;
    hasFetched = true;
    errorMessage = null;
    sections.clear();
    notifyListeners();
  }

  void setItemChecked(NotificationItem item, bool checked) {
    item.isChecked = checked;
    notifyListeners();
  }

  /// Fetch and parse notifications from /msg/others/.
  Future<void> fetchNotifications() async {
    isLoading = true;
    errorMessage = null;
    hasValidLatestCountsSnapshot = false;
    notifyListeners();

    try {
      String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found.');
      }


      const url = 'https://www.furaffinity.net/msg/others/';
      await FaRequestCoordinator.instance.waitForTurn(label: 'GET $url');
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
              'a=$cookieA; b=$cookieB',
            ),
            'Referer': 'https://www.furaffinity.net/msg/others/',
          },
        ),
      );
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        responseBody: response.statusCode == 403 ? response.data : null,
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to load notifications.');
      }

      final document = html_parser.parse(response.data.toString());

      // Find message-bar in both modern and classic formats
      final messageBar = document.querySelector('li.message-bar-desktop') ??
          document.querySelector('li.noblock');
      if (messageBar == null) {
        throw Exception('Notification counters not found.');
      }
      messageBarCounts.clear();
      final links = messageBar.querySelectorAll('a.notification-container');
      bool foundNotificationCounter = false;
      for (final link in links) {
        final href = link.attributes['href'] ?? '';
        final text = link.text.trim();
        final title = (link.attributes['title'] ?? '').trim();
        final typeKey =
            notificationTypeKeyFromHrefOrTitle(href: href, title: title);
        if (typeKey == null) continue;
        foundNotificationCounter = true;
        final int count = extractNotificationCount(
          title.isNotEmpty ? title : text,
        );
        if (count > 0) {
          messageBarCounts[typeKey] = count;
        }
      }
      if (!foundNotificationCounter) {
        throw Exception('Notification counters not found.');
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
      hasValidLatestCountsSnapshot = true;
      latestTopBarNotifications = Notifications(
        submissions: '$s',
        watches: '$w',
        journals: '$j',
        notes: '$n',
        comments: '$c',
        favorites: '$f',
        registeredUsersOnline: '$registeredUsersOnline',
      );

      currentUsername = extractNotificationMenubarUsername(document);
      currentUsernameFromLink = currentUsername;


      List<dom.Element> containers = document.querySelectorAll('section.section_container');
      if (containers.isEmpty) {
        containers = document.querySelectorAll('fieldset');
      }


      final formAction =
          document.querySelector('form#messages-form')?.attributes['action'] ?? '/msg/others/';

      List<NotificationSection> fetchedSections = [];
      for (var container in containers) {
        String heading = notificationSectionHeadingFromContainer(container);

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
                  linkUsername = extractNotificationUsernameFromHref(
                    avatarLink.attributes['href'],
                  );
                }
                if (av != null) {
                  avatarUrl =
                      normalizeNotificationImageUrl(av.attributes['src']);
                }
              }
              dom.Element? infoDiv = li.querySelector('div.info');
              if (infoDiv != null) {
                displayName = infoDiv.querySelector('span')?.text.trim();
              }


              dom.Element? avatarLink = li.querySelector('td.avatar a');
              if (avatarLink != null) {
                username = extractNotificationUsernameFromHref(
                  avatarLink.attributes['href'],
                );
              }

              String avatarHtml = li.querySelector('div.avatar')?.outerHtml ?? '';
              String infoHtml = li.querySelector('div.info')?.outerHtml ?? '';
              content = avatarHtml + infoHtml;
            } else {
              dom.Element? infoDiv = li.querySelector('div.info');
              if (infoDiv != null) {

                dom.Element? avatarLink = li.querySelector('div.avatar a');
                if (avatarLink != null) {
                  linkUsername = extractNotificationUsernameFromHref(
                    avatarLink.attributes['href'],
                  );
                }
                displayName = infoDiv.querySelector('span')?.text.trim();
                dom.Element? avatarImg = li.querySelector('div.avatar img.avatar');
                if (avatarImg != null) {
                  avatarUrl = normalizeNotificationImageUrl(
                    avatarImg.attributes['src'],
                  );
                }
                content = infoDiv.outerHtml;
              }
            }
          } else if (lowerHeading.contains('favorites')) {
            dom.Element? subLink = li.querySelector('a[href*="/view/"]');
            if (subLink != null) {
              url = subLink.attributes['href'];
              submissionId = extractNotificationSubmissionIdFromHref(url);
              content = content.replaceAll('"', '');
            }
          } else if (lowerHeading.contains('journal comments')) {
            dom.Element? journLink = li.querySelector('a[href*="/journal/"]');
            if (journLink != null) {
              url = journLink.attributes['href'];
              journalId = extractNotificationJournalIdFromHref(url);
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
              submissionId = extractNotificationSubmissionIdFromHref(url);
              content = content.replaceAll('"', '');
            }
            if (content.isNotEmpty) {
              content = content.substring(0, content.length - 1);
            }
          }
          else if (lowerHeading.contains('shouts')) {
            bool isClassic = document.querySelector('body')?.attributes['data-static-path'] == '/themes/classic';
            if (isClassic) {
              if (li.localName == 'table' && li.id.startsWith('shout-')) {
                if (li.text.trim() == 'Shout has been removed from your page.') {
                  content = 'Shout has been removed from your page.';
                } else {
                  dom.Element? av = li.querySelector('td.alt1 a img.avatar');
                  if (av != null) {
                    avatarUrl =
                        normalizeNotificationImageUrl(av.attributes['src']);
                  }
                  dom.Element? unameLink = li.querySelector('div.c-usernameBlock a.c-usernameBlock__displayName');
                  if (unameLink != null) {
                    username = unameLink.text.trim();
                    url = unameLink.attributes['href'];
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
                dom.Element? userLink = li.querySelector('a[href*="/user/"]');
                if (userLink != null) {
                  username = userLink.text.trim();
                  url = userLink.attributes['href'];
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
                  dom.Element? userLink = li.querySelector('a[href*="/user/"]');
                  if (userLink != null) {
                    username = userLink.text.trim();
                    url = userLink.attributes['href'];
                  }
                  dom.Element? av = li.querySelector('div.avatar img.avatar');
                  if (av != null) {
                    avatarUrl =
                        normalizeNotificationImageUrl(av.attributes['src']);
                  }
                }
              }
            } else {

              dom.Element? nameSpan = li.querySelector(
                  'span.c-usernameBlockSimple.username-underlined a[href*="/user/"] span.c-usernameBlockSimple__displayName'
              );
              if (nameSpan != null) {
                username = nameSpan.text.trim();
              }
              dom.Element? parentAnchor = li.querySelector(
                  'span.c-usernameBlockSimple.username-underlined a[href*="/user/"]'
              );
              if (parentAnchor != null) {
                url = parentAnchor.attributes['href'];
                String extracted = extractNotificationNicknameLink(li);
                if (extracted.isNotEmpty) {
                  username = username ?? "";

                }
              }
              dom.Element? avatarImg = li.querySelector('div.avatar img.avatar');
              if (avatarImg != null) {
                avatarUrl = normalizeNotificationImageUrl(
                  avatarImg.attributes['src'],
                );
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

            String finalNicknameLink = extractNotificationNicknameLink(li);


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
              journalId = extractNotificationJournalIdFromHref(url);
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


  static Future<List<Shout>> fetchProfileShouts(
    String myUsername, {
    bool forceRefresh = false,
  }) {
    return _shoutRepository.fetchProfileShouts(
      myUsername,
      forceRefresh: forceRefresh,
    );
  }

  static Future<List<Shout>> fetchMsgCenterShouts() {
    return _shoutRepository.fetchMsgCenterShouts();
  }

  static Future<List<Map<String, dynamic>>> fetchMsgOthersShouts() {
    return _shoutRepository.fetchMsgOthersShouts();
  }

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
      final url =
          'https://www.furaffinity.net${sections[sectionIndex].formAction}';
      await FaRequestCoordinator.instance.waitForTurn(label: 'POST $url');
      final response = await _dio.post(
        url,
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
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        responseBody: response.statusCode == 403 ? response.data : null,
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
      final url =
          'https://www.furaffinity.net${sections[sectionIndex].formAction}';
      await FaRequestCoordinator.instance.waitForTurn(label: 'POST $url');
      final response = await _dio.post(
        url,
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
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        responseBody: response.statusCode == 403 ? response.data : null,
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
        final url = 'https://www.furaffinity.net${sections[i].formAction}';
        await FaRequestCoordinator.instance.waitForTurn(label: 'POST $url');
        final resp = await _dio.post(
          url,
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
        FaRequestCoordinator.instance.recordHttpStatus(
          statusCode: resp.statusCode,
          responseBody: resp.statusCode == 403 ? resp.data : null,
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



  static Future<String?> fetchAvatarUrl(String username) {
    return _mediaRepository.fetchAvatarUrl(username);
  }

  static Future<String?> fetchSubmissionPreview(String submissionId) {
    return _mediaRepository.fetchSubmissionPreview(submissionId);
  }
}
