import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';
import 'package:FANotifier/features/notifications/domain/fa_notification_models.dart';

/// Provider managing notifications from Fur Affinity.
class NotificationsProvider with ChangeNotifier {
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

  /// The username extracted from #my-username (e.g. "username").
  String? currentUsername;

  NotificationsProvider() {
    _initializeDio();
    fetchNotifications();
  }


  void clearAllNotifications() {
    isLoading = false;
    hasFetched = true;
    errorMessage = null;
    sections.clear();
    notifyListeners();
  }


  Future<void> _initializeDio() async {
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.headers['Accept'] =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,'
        'image/apng,*/*;q=0.8';
    _dio.options.headers['Accept-Encoding'] = 'gzip, deflate, br, zstd';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9,ru;q=0.8';
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) {
      return status != null && status >= 200 && status < 600;
    };
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

      debugPrint("[fetchNotifications] Response code: ${response.statusCode}");
      if (response.statusCode != 200) {
        throw Exception('Failed to load notifications.');
      }

      final responseHtml = response.data.toString();
      final document = html_parser.parse(responseHtml);

      // Gets currentUsername from #my-username
      final userElement = document.getElementById('my-username');
      if (userElement != null) {
        final href = userElement.attributes['href'];
        if (href != null) {
          final reg = RegExp(r'^/user/([^/]+)/?$');
          final match = reg.firstMatch(href);
          if (match != null) {
            currentUsername = match.group(1);
            debugPrint("[fetchNotifications] Found currentUsername=$currentUsername");
          }
        }
      }


      List<dom.Element> sectionContainers =
      document.querySelectorAll('section.section_container');
      if (sectionContainers.isEmpty) {
        sectionContainers = document.querySelectorAll('fieldset');
      }

      debugPrint("[fetchNotifications] Found ${sectionContainers.length} container(s).");
      // The <form> action used for removing/nuking items
      final formAction = document.querySelector('form#messages-form')
          ?.attributes['action'] ??
          '/msg/others/';

      final List<NotificationSection> fetchedSections = [];

      for (var container in sectionContainers) {
        // e.g. "New shouts" => "Shouts"
        String heading = (container.querySelector('h2') ??
            container.querySelector('h3'))
            ?.text
            .trim() ??
            'No Title';
        heading = heading.replaceFirst(RegExp(r'^New\s+', caseSensitive: false), '');

        // If the heading is not empty, we uppercase the first letter
        if (heading.isNotEmpty) {
          heading = heading[0].toUpperCase() + heading.substring(1);
        }

        // Grab <li> items that are not "section-controls"
        final liItems = container
            .querySelectorAll('ul.message-stream > li')
            .where((li) => !li.classes.contains('section-controls'))
            .toList();

        final List<NotificationItem> items = [];
        for (var li in liItems) {
          final checkbox = li.querySelector('input[type="checkbox"]');
          final id = checkbox?.attributes['value'] ?? '';

          // Extract date from .popup_date
          String date = '';
          String fullDate = '';
          final dateElm = li.querySelector('.popup_date');
          if (dateElm != null) {
            date = dateElm.text.trim();
            fullDate = dateElm.attributes['title'] ?? date;
            dateElm.remove();
          }


          String content = li.innerHtml.trim();
          content = content.replaceAll(RegExp(r'<input[^>]*>'), '').trim();

          String? username;
          String? submissionId;
          String? journalId;
          String? url;
          String? avatarUrl;
          final lowerHeading = heading.toLowerCase();

          if (lowerHeading.contains('watches')) {
            // watchers
            final tableElem = li.querySelector('table');
            if (tableElem != null) {
              final av = tableElem.querySelector('td.avatar a img.avatar');
              if (av != null) {
                avatarUrl = av.attributes['src'];
                if (avatarUrl != null && avatarUrl.startsWith('//')) {
                  avatarUrl = 'https:$avatarUrl';
                }
              }
            }
            final infoDiv = li.querySelector('div.info');
            if (infoDiv != null) {
              username = infoDiv.querySelector('span')?.text.trim();
            }
            final avatarLink = li.querySelector('div.avatar a');
            if (avatarLink != null) {
              url = avatarLink.attributes['href'];
            }

            final avatarHtml = li.querySelector('div.avatar')?.outerHtml ?? '';
            final infoHtml = li.querySelector('div.info')?.outerHtml ?? '';
            content = avatarHtml + infoHtml;

          } else if (lowerHeading.contains('favorites')) {
            // "New favorites"
            final subLink = li.querySelector('a[href*="/view/"]');
            if (subLink != null) {
              url = subLink.attributes['href'];
              final match = RegExp(r'^/view/(\d+)/.*$').firstMatch(url ?? '');
              if (match != null) {
                submissionId = match.group(1);
              }
            }

          } else if (lowerHeading.contains('journal comments')) {
            final journLink = li.querySelector('a[href*="/journal/"]');
            if (journLink != null) {
              url = journLink.attributes['href'];
              final match = RegExp(r'^/journal/(\d+)/.*$').firstMatch(url ?? '');
              if (match != null) {
                journalId = match.group(1);
              }
            }

          } else if (lowerHeading.contains('submission comments')) {
            final subLink = li.querySelector('a[href*="/view/"]');
            if (subLink != null) {
              url = subLink.attributes['href'];
              final match = RegExp(r'^/view/(\d+)/.*$').firstMatch(url ?? '');
              if (match != null) {
                submissionId = match.group(1);
              }
            }

          } else if (lowerHeading.contains('shouts')) {
            // Shouts
            if (li.localName == 'table' && li.id.startsWith('shout-')) {

              if (li.text.trim() == 'Shout has been removed from your page.') {
                content = 'Shout has been removed from your page.';
              } else {
                final av = li.querySelector('td.alt1 a img.avatar');
                if (av != null) {
                  avatarUrl = av.attributes['src'];
                  if (avatarUrl != null && avatarUrl.startsWith('//')) {
                    avatarUrl = 'https:$avatarUrl';
                  }
                }
                final unameLink = li.querySelector('div.c-usernameBlock a.c-usernameBlock__displayName');
                if (unameLink != null) {
                  username = unameLink.text.trim();
                  url = unameLink.attributes['href'];
                }
                final dateElem = li.querySelector('span.popup_date');
                if (dateElem != null) {
                  date = dateElem.text.trim();
                  fullDate = dateElem.attributes['title'] ?? date;
                  dateElem.remove();
                }
                final contentDiv = li.querySelector('td.alt1.addpad div.no_overflow');
                if (contentDiv != null) {
                  content = contentDiv.text.trim();
                } else {
                  content = li.text.trim();
                }
              }
            } else if (li.querySelector('input[type="checkbox"][name="shouts[]"]') != null) {
              // Classic "shouts[]"
              final userLink = li.querySelector('a[href^="/user/"]');
              if (userLink != null) {
                username = userLink.text.trim();
                url = userLink.attributes['href'];
              }
              final dateElem = li.querySelector('span.popup_date');
              if (dateElem != null) {
                date = dateElem.text.trim();
                fullDate = dateElem.attributes['title'] ?? date;
                dateElem.remove();
              }
              content = li.text.trim();
            } else {
              // fallback or removed
              if (li.text.contains('Shout has been removed')) {
                content = 'Shout has been removed from your page.';
              } else {
                final userLink = li.querySelector('a[href^="/user/"]');
                if (userLink != null) {
                  username = userLink.text.trim();
                  url = userLink.attributes['href'];
                }
                final av = li.querySelector('div.avatar img.avatar');
                if (av != null) {
                  avatarUrl = av.attributes['src'];
                  if (avatarUrl != null && avatarUrl.startsWith('//')) {
                    avatarUrl = 'https:$avatarUrl';
                  }
                }
              }
            }

          } else if (lowerHeading.contains('journals')) {
            final journLink = li.querySelector('a[href*="/journal/"]');
            if (journLink != null) {
              url = journLink.attributes['href'];
              final match = RegExp(r'^/journal/(\d+)/.*$').firstMatch(url ?? '');
              if (match != null) {
                journalId = match.group(1);
              }
            }
          }

          items.add(
            NotificationItem(
              id: id,
              content: content,
              username: username,
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

      sections = fetchedSections;
      debugPrint("[fetchNotifications] Final parsed sections: "
          "${sections.map((s) => s.title).toList()}");

      // If there's a "Shouts" section, check if there's at least one real shout
      final shoutsIndex = sections.indexWhere(
            (s) => s.title.toLowerCase().contains('shouts'),
      );
      if (shoutsIndex != -1) {
        bool anyReal = sections[shoutsIndex].items.any(
              (item) => item.content.trim() != 'Shout has been removed from your page.',
        );
        if (anyReal && currentUsername != null) {
          debugPrint("[fetchNotifications] Real shouts found => fetch profile shouts.");
          await _fetchProfileShouts();
        } else {
          debugPrint("[fetchNotifications] Only removal messages or no username => skip profile fetch.");
        }
      } else {
        debugPrint("[fetchNotifications] No shouts section found in notifications.");
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

  /// Fetch shouts from the user’s profile page in classic style (tables).
  Future<void> _fetchProfileShouts() async {
    if (currentUsername == null) return;
    try {
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        debugPrint("[_fetchProfileShouts] Missing cookies => skip");
        return;
      }

      final profileUrl = 'https://www.furaffinity.net/user/$currentUsername/';
      debugPrint("[_fetchProfileShouts] GET $profileUrl");
      await FaRequestCoordinator.instance.waitForTurn(label: 'GET $profileUrl');
      final resp = await _dio.get(
        profileUrl,
        options: Options(
          headers: {
            'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
              'a=$cookieA; b=$cookieB',
            ),
            'Referer': profileUrl,
          },
        ),
      );
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: resp.statusCode,
        responseBody: resp.statusCode == 403 ? resp.data : null,
      );
      debugPrint("[_fetchProfileShouts] code: ${resp.statusCode}");
      if (resp.statusCode != 200) return;

      final doc = html_parser.parse(resp.data.toString());
      final shoutTables = doc.querySelectorAll('table[id^="shout-"]');
      debugPrint("[_fetchProfileShouts] Found ${shoutTables.length} shout table(s).");

      final List<NotificationItem> profileShouts = [];
      for (var t in shoutTables) {
        final tableId = t.attributes['id'] ?? '';
        if (!tableId.startsWith('shout-')) continue;

        String? avatar;
        final avatarImg = t.querySelector('td.alt1 a img.avatar');
        if (avatarImg != null) {
          avatar = avatarImg.attributes['src'];
          if (avatar != null && avatar.startsWith('//')) {
            avatar = 'https:$avatar';
          }
        }

        String? uname;
        String? link;
        final unameLink =
        t.querySelector('div.c-usernameBlock a.c-usernameBlock__displayName');
        if (unameLink != null) {
          uname = unameLink.text.trim();
          link = unameLink.attributes['href'];
        }

        String dt = '';
        String dtFull = '';
        final dateElem = t.querySelector('span.popup_date');
        if (dateElem != null) {
          dt = dateElem.text.trim();
          dtFull = dateElem.attributes['title'] ?? dt;
        }

        String text = '';
        final contentDiv = t.querySelector('td.alt1.addpad div.no_overflow');
        if (contentDiv != null) {
          text = contentDiv.text.trim();
        }

        profileShouts.add(
          NotificationItem(
            id: tableId,
            content: text,
            username: uname,
            url: link,
            avatarUrl: avatar,
            date: dt,
            fullDate: dtFull,
          ),
        );
      }

      int index = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
      if (index != -1) {
        debugPrint("[_fetchProfileShouts] Overwriting with ${profileShouts.length} table-based shouts.");
        sections[index].items = profileShouts;
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint("[_fetchProfileShouts] Error: $e\n$st");
    }
  }

  /// Toggle selection of all items in a given section.
  void toggleSelectAll(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    bool shouldSelectAll = sections[sectionIndex].items.any((item) => !item.isChecked);
    for (var item in sections[sectionIndex].items) {
      item.isChecked = shouldSelectAll;
    }
    notifyListeners();
  }

  /// Remove selected items (e.g. remove-shouts).
  Future<void> removeSelected(int sectionIndex) async {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    final selectedItems = sections[sectionIndex].items.where((item) => item.isChecked).toList();
    if (selectedItems.isEmpty) return;

    isLoading = true;
    notifyListeners();
    try {
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found.');
      }

      final titleLower = sections[sectionIndex].title.toLowerCase();
      final formData = <String, dynamic>{};

      if (titleLower.contains('shouts')) {
        formData['remove-shouts'] = 'Remove Selected Shouts';
        formData['shouts'] = selectedItems.map((x) => x.id).toList();
      } else if (titleLower.contains('watches')) {
        formData['remove-watches'] = 'Remove Selected Watches';
        formData['watches'] = selectedItems.map((x) => x.id).toList();
      } else if (titleLower.contains('submission comments')) {
        formData['remove-submission-comments'] = 'Remove Selected Comments';
        formData['comments-submissions'] = selectedItems.map((x) => x.id).toList();
      } else if (titleLower.contains('journal comments')) {
        formData['remove-journal-comments'] = 'Remove Selected Comments';
        formData['comments-journals'] = selectedItems.map((x) => x.id).toList();
      } else if (titleLower.contains('favorites')) {
        formData['remove-favorites'] = 'Remove Selected Favorites';
        formData['favorites'] = selectedItems.map((x) => x.id).toList();
      } else if (titleLower.contains('journals')) {
        formData['remove-journals'] = 'Remove Selected Journals';
        formData['journals'] = selectedItems.map((x) => x.id).toList();
      }

      final dioFormData = FormData();
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

      if (titleLower.contains('shouts')) {
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

  /// Update the Shouts section with new data (if needed).
  void updateShouts(List<dynamic> newShouts) {
    final idx = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return;
    final updated = <NotificationItem>[];
    for (var sh in newShouts) {
      final oldItem = sections[idx].items.firstWhere(
            (o) => o.id == sh.id,
        orElse: () => NotificationItem(
          id: sh.id,
          content: sh.textContent,
          username: sh.nickname,
          avatarUrl: sh.avatarUrl,
          date: sh.postedAgo,
          fullDate: sh.postedTitle,
        ),
      );
      updated.add(
        NotificationItem(
          id: sh.id,
          content: sh.textContent,
          username: sh.nickname,
          avatarUrl: sh.avatarUrl,
          date: sh.postedAgo,
          fullDate: sh.postedTitle,
          isChecked: oldItem.isChecked,
        ),
      );
    }
    sections[idx].items = updated;
    notifyListeners();
  }

  /// Mark/unmark a single shout by ID.
  void setShoutCheckedById(String id, bool isChecked) {
    final idx = sections.indexWhere((s) => s.title.toLowerCase().contains('shouts'));
    if (idx == -1) return;
    for (final item in sections[idx].items) {
      if (item.id == id) {
        item.isChecked = isChecked;
        notifyListeners();
        break;
      }
    }
  }

  /// Nuke an entire section at once (e.g. "nuke-shouts").
  Future<void> nukeSection(int sectionIndex) async {
    if (sectionIndex < 0 || sectionIndex >= sections.length) return;
    isLoading = true;
    notifyListeners();
    try {
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found.');
      }

      final tLower = sections[sectionIndex].title.toLowerCase();
      final formData = <String, dynamic>{};

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

      final dioFormData = FormData();
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

  /// Remove all items in all sections (global).
  Future<void> removeAllNotifications() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found.');
      }

      for (int i = sections.length - 1; i >= 0; i--) {
        final items = sections[i].items;
        if (items.isEmpty) continue;

        final headingLower = sections[i].title.toLowerCase();
        final formData = <String, dynamic>{};

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

        final dioFormData = FormData();
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
}
