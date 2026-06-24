import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/core/utils/utils.dart';
import 'package:FANotifier/features/notes/domain/note_reply_models.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';
import 'package:FANotifier/shared/fa/fa_system_message_parser.dart';

class NoteReplyService {
  NoteReplyService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ) {
    _initializeDio();
  }

  final FlutterSecureStorage _secureStorage;
  final Dio _dio = Dio();
  final CookieJar _cookieJar = CookieJar();

  void close() {
    _dio.close();
  }

  Future<NoteReplyContext> fetchReplyContext(String messageLink) async {
    await _loadCookies();
    await FaRequestCoordinator.instance.waitForTurn(
      label: 'GET https://www.furaffinity.net$messageLink',
    );
    final response = await _dio.get(
      'https://www.furaffinity.net$messageLink',
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        },
      ),
    );

    FaRequestCoordinator.instance.recordHttpStatus(
      statusCode: response.statusCode,
      responseBody: response.statusCode == 403 ? response.data : null,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch details: status ${response.statusCode}');
    }

    final doc = html_parser.parse(response.data);

    final isClassicTheme = doc.querySelector(
          'body[data-static-path="/themes/classic"][id="pageid-messagecenter-pms-view"]',
        ) !=
        null;

    var recipient = 'Loading...';
    if (isClassicTheme) {
      final classicSpan = doc.querySelector('span[style*="color: #999999"]');
      if (classicSpan != null) {
        final userNameAnchors = classicSpan.querySelectorAll(
          'a.c-usernameBlock__userName.js-userName-block',
        );
        if (userNameAnchors.isNotEmpty) {
          final senderAnchor = userNameAnchors.first;
          final href = senderAnchor.attributes['href'] ?? '';
          final parts = href.split('/');
          if (parts.length >= 3) {
            recipient = parts[2];
          }
        }

        if (recipient == 'Loading...') {
          final displayNameAnchors = classicSpan.querySelectorAll(
            'a.c-usernameBlock__displayName.js-displayName-block',
          );
          if (displayNameAnchors.isNotEmpty) {
            final senderAnchor = displayNameAnchors.first;
            final href = senderAnchor.attributes['href'] ?? '';
            final parts = href.split('/');
            if (parts.length >= 3) {
              recipient = parts[2];
            }
          }
        }
      }
      if (recipient == 'Loading...') {
        recipient = 'UnknownRecipient';
      }
    } else {
      recipient = (doc
                  .querySelector(
                    '.message-center-note-information .addresses a:last-child',
                  )
                  ?.text
                  .trim() ??
              'Unknown recipient')
          .replaceFirst(RegExp(r'^.'), '');

      if (recipient == 'Loading...') {
        recipient = 'UnknownRecipient';
      }
    }

    return NoteReplyContext(
      recipient: recipient,
      isClassicTheme: isClassicTheme,
    );
  }

  Future<NoteReplySendResult> sendModernReply({
    required String messageLink,
    required String recipient,
    required String subject,
    required String replyText,
    required String originalContent,
  }) async {
    try {
      await _loadCookies();
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Not logged in or missing cookies.');
      }

      late final String msgId;
      late final int pageNo;
      if (messageLink.contains('/viewmessage/')) {
        final match = RegExp(r'/viewmessage/(\d+)/').firstMatch(messageLink);
        if (match != null) {
          msgId = match.group(1)!;
          pageNo = 1;
        } else {
          throw Exception('Invalid message ID from link: $messageLink');
        }
      } else {
        pageNo = extractPageNumber(messageLink);
        msgId = extractMessageId(messageLink);
        if (msgId.isEmpty) {
          throw Exception('Invalid message ID from link: $messageLink');
        }
      }

      final getUrl = 'https://www.furaffinity.net/msg/pms/$pageNo/$msgId/#message';
      await FaRequestCoordinator.instance.waitForTurn(
        label: 'GET $getUrl',
      );
      final getResp = await _dio.get(
        getUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': getUrl,
            'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
              'a=$cookieA; b=$cookieB',
            ),
          },
          followRedirects: false,
        ),
      );

      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: getResp.statusCode,
        responseBody: getResp.statusCode == 403 ? getResp.data : null,
      );

      if (getResp.statusCode == 302) {
        throw Exception("GET request was redirected (auth issue?)");
      }

      final doc = html_parser.parse(getResp.data);
      final keyInput = doc.querySelector('form#note-form input[name="key"]');
      final keyValue = keyInput?.attributes['value'] ?? '';
      if (keyValue.isEmpty) {
        throw Exception("Failed to find the 'key' hidden field in the note form.");
      }

      final formData = {
        'key': keyValue,
        'to': recipient,
        'subject': subject,
        'message': '$replyText\n\n—————————\n$originalContent',
      };
      final encodedFormData = Uri(queryParameters: formData).query;
      const sendMessageUrl = 'https://www.furaffinity.net/msg/send/';

      await FaRequestCoordinator.instance.waitForTurn(
        label: 'POST $sendMessageUrl',
      );
      final postResp = await _dio.post(
        sendMessageUrl,
        data: encodedFormData,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://www.furaffinity.net',
            'Referer': getUrl,
            'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
              'a=$cookieA; b=$cookieB',
            ),
          },
          followRedirects: false,
        ),
      );

      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: postResp.statusCode,
        responseBody: postResp.statusCode == 403 ? postResp.data : null,
      );

      if (postResp.statusCode == 302) {
        return const NoteReplySendResult(success: true);
      }

      final faMessage = parseFaSystemMessage(postResp.data);
      if (faMessage != null) {
        if (faMessage.isMaintenanceOrUnavailable) {
          FaRequestCoordinator.instance.recordMaintenanceOrUnavailable(
            message: faMessage.message,
            retryAfter: faMessage.retryAfter,
          );
        }
        return NoteReplySendResult(
          success: false,
          errorMessage: faMessage.message,
          retryAfterSeconds: faMessage.retryAfter?.inSeconds,
        );
      }

      return NoteReplySendResult(
        success: false,
        errorMessage: 'Failed to send reply: ${postResp.statusCode}',
      );
    } catch (e) {
      return NoteReplySendResult(
        success: false,
        errorMessage: 'Error sending reply: $e',
      );
    }
  }

  void _initializeDio() {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) =>
        status != null && status >= 200 && status < 600;
  }

  Future<void> _loadCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final cookies = <Cookie>[];
    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));

    final uri = Uri.parse('https://www.furaffinity.net');
    _cookieJar.saveFromResponse(
      uri,
      await FaCookieHelper.addCfClearanceCookie(cookies),
    );
  }
}
