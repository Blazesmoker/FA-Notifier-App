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

import 'message_model.dart';
import '../parsing_utils.dart';
import '../utils.dart';
import '../utils/notes_notifications_text_edit.dart';
import '../services/fa_http.dart';

class NotesApiService {
  NotesApiService(this._secureStorage);

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
      final resp = await client
          .get(
            Uri.parse(url),
            headers: {
              'Cookie': 'a=$cookieA; b=$cookieB; folder=$folder',
              'User-Agent': FAHttp.userAgent,
              HttpHeaders.connectionHeader: 'close',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 30));
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
          final doc = html_parser.parse(decoded);
          final bool isClassic =
              doc.querySelector('body[data-static-path="/themes/classic"]') !=
                  null;

          var noteElements =
              doc.querySelectorAll('#notes-list .note-list-container');
          if (noteElements.isEmpty && isClassic) {
            List<dom.Element> classicRows =
                List.from(doc.querySelectorAll('#notes-list tr.note'));
            if (classicRows.isNotEmpty &&
                classicRows.last.querySelector('input[type="checkbox"]') ==
                    null) {
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
                noteEl
                    .querySelector('a.notelink.note-read.read')
                    ?.text
                    .trim() ??
                noteEl
                    .querySelector('a.notelink.note-unread.unread')
                    ?.text
                    .trim() ??
                'No subject';

            final sender = noteEl
                    .querySelector(
                        '.c-usernameBlock__displayName .js-displayName')
                    ?.text
                    .trim() ??
                noteEl
                    .querySelector(
                        'div.c-usernameBlock.marquee-container a.c-usernameBlock__displayName.js-displayName-block span.js-displayName')
                    ?.text
                    .trim() ??
                'Unknown sender';

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
              date: date,
              link: link,
              isUnread: isUnread,
            ));
          }
          return fetched;
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
      } catch (e) {
        throw Exception('Error fetching page $page: $e');
      }
    }
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
      [Cookie('a', cookieA), Cookie('b', cookieB)],
    );
    final resp = await dio.get(
      'https://www.furaffinity.net$link',
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': FAHttp.userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          HttpHeaders.connectionHeader: 'close',
        },
        validateStatus: (status) => status != null && status >= 200 && status < 400,
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

        final rawHtml = modernContentElement.innerHtml;
        final innerDoc = html_parser.parse(rawHtml);

        innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
          final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
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
            final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
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
}

