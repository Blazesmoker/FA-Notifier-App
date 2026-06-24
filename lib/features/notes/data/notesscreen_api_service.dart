import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/features/notifications/domain/notification_counts.dart';
import 'package:FANotifier/core/utils/utils.dart';
import 'package:FANotifier/shared/utils/notes_notifications_text_edit.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';
import 'package:FANotifier/shared/fa/fa_system_message_parser.dart';

class NotesPageSnapshot {
  const NotesPageSnapshot({
    required this.messages,
    required this.topbarCounts,
  });

  final List<Message> messages;
  final NotificationCounts? topbarCounts;
}

class NotesApiService {
  NotesApiService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<http.Response> _faGet({
    required String url,
    required String cookieA,
    required String cookieB,
    required String folder,
  }) async {
    final ioHttp = HttpClient()
      ..idleTimeout = Duration.zero
      ..connectionTimeout = const Duration(seconds: 20);
    final client = IOClient(ioHttp);
    try {
      await FaRequestCoordinator.instance.waitForTurn(
        label: 'GET $url',
      );
      final resp = await client.get(
        Uri.parse(url),
        headers: {
          'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
            'a=$cookieA; b=$cookieB; folder=$folder',
          ),
          'User-Agent': FAHttp.userAgent,
          HttpHeaders.connectionHeader: 'close',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 30));
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: resp.statusCode,
        headers: resp.headers,
        responseBody: resp.statusCode == 403 ? resp.body : null,
      );
      return resp;
    } finally {
      client.close();
      ioHttp.close(force: true);
    }
  }

  Future<List<Message>> fetchNotesPage({
    required String folder,
    required int page,
  }) async {
    final snapshot = await fetchNotesPageSnapshot(folder: folder, page: page);
    return snapshot.messages;
  }

  Future<NotesPageSnapshot> fetchNotesPageSnapshot({
    required String folder,
    required int page,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('No cookies => user not logged in?');
    }

    const int maxRetries = 4;
    int retry = 0;
    Duration backoff = const Duration(seconds: 2);
    debugPrint("Fetching page $page in notes screen");
    while (true) {
      try {
        final resp = await _faGet(
          url: 'https://www.furaffinity.net/msg/pms/$page/',
          cookieA: cookieA,
          cookieB: cookieB,
          folder: folder,
        );

        if (resp.statusCode == 200) {
          final decoded = utf8.decode(resp.bodyBytes, allowMalformed: true);
          final faMessage = parseFaSystemMessage(decoded);
          if (faMessage != null) {
            if (faMessage.isMaintenanceOrUnavailable) {
              FaRequestCoordinator.instance.recordMaintenanceOrUnavailable(
                message: faMessage.message,
                retryAfter: faMessage.retryAfter,
              );
              throw FaMaintenanceUnavailableException(faMessage.message);
            }
            throw Exception(faMessage.message);
          }
          final doc = html_parser.parse(decoded);
          return NotesPageSnapshot(
            messages: _parseMessages(doc),
            topbarCounts: _parseTopbarCounts(doc),
          );
        } else if (resp.statusCode == 503) {
          retry++;
          if (retry > maxRetries) {
            throw Exception('HTTP 503 after $maxRetries retries');
          }
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        } else {
          throw Exception('HTTP error ${resp.statusCode} for page=$page');
        }
      } on TimeoutException catch (e) {
        retry++;
        if (retry > maxRetries) {
          throw Exception('Timeout after $maxRetries retries: $e');
        }
        await Future.delayed(backoff);
        backoff *= 2;
        continue;
      } on SocketException catch (e) {
        retry++;
        if (retry > maxRetries) {
          throw Exception('SocketException after $maxRetries retries: $e');
        }
        await Future.delayed(backoff);
        backoff *= 2;
        continue;
      } on FaMaintenanceUnavailableException {
        rethrow;
      } catch (e) {
        throw Exception('Error fetching page $page: $e');
      }
    }
  }

  List<Message> _parseMessages(dom.Document doc) {
    final bool isClassic =
        doc.querySelector('body[data-static-path="/themes/classic"]') != null;

    var noteElements = doc.querySelectorAll('#notes-list .note-list-container');
    if (noteElements.isEmpty && isClassic) {
      List<dom.Element> classicRows =
          List.from(doc.querySelectorAll('#notes-list tr.note'));
      if (classicRows.isNotEmpty &&
          classicRows.last.querySelector('input[type="checkbox"]') == null) {
        classicRows.removeLast();
      }
      noteElements = classicRows;
    }

    final List<Message> fetched = [];
    for (var noteEl in noteElements) {
      final subject = noteEl
              .querySelector(
                  '.note-list-subject-container .c-noteListItem__subject')
              ?.text
              .trim() ??
          noteEl.querySelector('a.notelink.note-read.read')?.text.trim() ??
          noteEl.querySelector('a.notelink.note-unread.unread')?.text.trim() ??
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

      final displayNameEls = noteEl
          .querySelectorAll('.c-usernameBlock__displayName .js-displayName');
      final recipient = displayNameEls.length > 1
          ? (displayNameEls.elementAt(1).text.trim())
          : '';

      final date = noteEl
              .querySelector('.note-list-senddate span')
              ?.attributes['title'] ??
          noteEl
              .querySelector('td.alt1.nowrap span.popup_date')
              ?.attributes['title'] ??
          '';

      final link = noteEl
              .querySelector('.note-list-subject-container a')
              ?.attributes['href'] ??
          noteEl
              .querySelector('a.notelink.note-unread.unread')
              ?.attributes['href'] ??
          noteEl
              .querySelector('a.notelink.note-read.read')
              ?.attributes['href'] ??
          '';

      final isUnread = (noteEl.querySelector('img.unread') != null ||
          noteEl.querySelector('img[src*="pms-unread.png"]') != null);

      final id = extractMessageId(link);

      fetched.add(Message(
        id: id,
        subject: subject,
        sender: sender,
        recipient: recipient,
        date: date,
        link: link,
        isUnread: isUnread,
      ));
    }
    return fetched;
  }

  NotificationCounts? _parseTopbarCounts(dom.Document doc) {
    final links = doc.querySelectorAll(
      'li.message-bar-desktop a.notification-container, li.noblock a.notification-container',
    );
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
      final key = _topbarTypeKey(href: href, title: title);
      if (key == null) continue;
      counts[key] = _extractTopbarCount(title.isNotEmpty ? title : text);
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

  String? _topbarTypeKey({
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

  int _extractTopbarCount(String text) {
    final match = RegExp(r'\d{1,3}(?:[,.]\d{3})*|\d+').firstMatch(text);
    if (match == null) return 0;
    return int.tryParse(match.group(0)!.replaceAll(RegExp(r'[,.]'), '')) ?? 0;
  }

  Future<String> fetchMessageContent(String link) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('No cookies => not logged in');
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
    final url = 'https://www.furaffinity.net$link';
    await FaRequestCoordinator.instance.waitForTurn(label: 'GET $url');
    final resp = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': FAHttp.userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          HttpHeaders.connectionHeader: 'close',
        },
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    FaRequestCoordinator.instance.recordHttpStatus(
      statusCode: resp.statusCode,
      responseBody: resp.statusCode == 403 ? resp.data : null,
    );
    if (resp.statusCode == 200) {
      final doc = html_parser.parse(resp.data);

      final modernContentElement =
          doc.querySelector('.section-body .user-submitted-links');
      if (modernContentElement != null) {
        modernContentElement
            .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
            .forEach((e) => e.remove());

        final rawHtml = modernContentElement.innerHtml;
        final innerDoc = html_parser.parse(rawHtml);

        innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
          final fullLink =
              anchor.attributes['title'] ?? anchor.attributes['href'];
          if (fullLink != null) {
            anchor.innerHtml = fullLink;
          }
        });

        final updatedText = innerDoc.body?.text.trim() ?? '';
        final newestContent = extractNewestContent(updatedText);
        return newestContent.isNotEmpty ? newestContent : 'No content';
      } else {
        final classicContentElement = doc.querySelector('td.noteContent.alt1');
        if (classicContentElement != null) {
          classicContentElement
              .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
              .forEach((e) => e.remove());
          classicContentElement
              .querySelector('span[style*="color: #999999"]')
              ?.remove();

          final rawHtml = classicContentElement.innerHtml;
          final innerDoc = html_parser.parse(rawHtml);

          innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
            final fullLink =
                anchor.attributes['title'] ?? anchor.attributes['href'];
            if (fullLink != null) {
              anchor.innerHtml = fullLink;
            }
          });

          final updatedText = innerDoc.body?.text.trim() ?? '';
          final newestContent = extractNewestContent(updatedText);
          return newestContent.isNotEmpty ? newestContent : 'No content';
        }
      }
      return 'No content';
    } else {
      throw Exception('Failed to fetch => ${resp.statusCode}');
    }
  }

  /// Fetches trash notes. Uses folder=trash in cookie with /msg/pms/.
  Future<List<Message>> fetchTrashPage({required int page}) async {
    return fetchNotesPage(folder: 'trash', page: page);
  }

  /// Restores notes from Trash. POST with move_to=restore, folder=trash in cookie.
  Future<void> restoreNotesFromTrash({required List<String> ids}) async {
    if (ids.isEmpty) return;
    await _moveNotesInTrash(ids: ids, moveTo: 'restore');
  }

  /// Permanently deletes notes from Trash. POST with move_to=delete, folder=trash in cookie.
  Future<void> deleteNotesPermanently({required List<String> ids}) async {
    if (ids.isEmpty) return;
    await _moveNotesInTrash(ids: ids, moveTo: 'delete');
  }

  Future<void> _moveNotesInTrash({
    required List<String> ids,
    required String moveTo,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('No cookies => user not logged in?');
    }
    final body = 'manage_notes=1&move_to=$moveTo&'
        '${ids.map((id) => 'items[]=${Uri.encodeComponent(id)}').join('&')}';
    final resp = await FAHttp.post(
      Uri.parse('https://www.furaffinity.net/msg/pms/'),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB; folder=trash',
        ),
        HttpHeaders.connectionHeader: 'close',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Referer': 'https://www.furaffinity.net/controls/switchbox/trash/',
        'Origin': 'https://www.furaffinity.net',
      },
      body: body,
      timeout: const Duration(seconds: 30),
    );
    if (resp.statusCode != 200 && resp.statusCode != 302) {
      throw Exception('$moveTo request failed: ${resp.statusCode}');
    }
  }

  /// Moves the given note ids to Trash. [folder] is 'inbox' or 'sent'.
  /// POST to https://www.furaffinity.net/msg/pms/ with manage_notes=1, move_to=trash, items[]=id...
  Future<void> moveNotesToTrash({
    required List<String> ids,
    required String folder,
  }) async {
    if (ids.isEmpty) return;
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('No cookies => user not logged in?');
    }
    final body = 'manage_notes=1&move_to=trash&'
        '${ids.map((id) => 'items[]=${Uri.encodeComponent(id)}').join('&')}';
    final resp = await FAHttp.post(
      Uri.parse('https://www.furaffinity.net/msg/pms/'),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB; folder=$folder',
        ),
        HttpHeaders.connectionHeader: 'close',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Referer': 'https://www.furaffinity.net/msg/pms/',
        'Origin': 'https://www.furaffinity.net',
      },
      body: body,
      timeout: const Duration(seconds: 30),
    );
    if (resp.statusCode != 200 && resp.statusCode != 302) {
      throw Exception('Trash request failed: ${resp.statusCode}');
    }
  }
}
