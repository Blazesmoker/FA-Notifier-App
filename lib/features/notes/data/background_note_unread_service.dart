import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/core/utils/utils.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/core/fa/fa_cookie_helper.dart';
import 'package:FANotifier/core/network/fa_http.dart';
import 'package:FANotifier/core/network/fa_request_coordinator.dart';

class BackgroundNoteUnreadService {
  BackgroundNoteUnreadService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<void> markAsUnread(Message message) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
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
    int pageNumber = extractPageNumber(message.link);
    String messageId = extractMessageId(message.link);
    if (messageId.isEmpty) {
      final classicMatch =
          RegExp(r'/viewmessage/(\d+)/').firstMatch(message.link);
      if (classicMatch != null) {
        messageId = classicMatch.group(1)!;
        pageNumber = 1;
      } else {
        throw Exception('Invalid message ID');
      }
    }
    final formData = {
      'manage_notes': '1',
      'items[]': messageId,
      'move_to': 'unread',
    };
    final url =
        'https://www.furaffinity.net/msg/pms/$pageNumber/$messageId/';
    await FaRequestCoordinator.instance.waitForTurn(label: 'POST $url');
    final response = await dio.post(
      url,
      data: formData,
      options: Options(
        headers: {
          'User-Agent': FAHttp.userAgent,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer':
              'https://www.furaffinity.net/msg/pms/$pageNumber/$messageId/',
          'Origin': 'https://www.furaffinity.net',
        },
        followRedirects: false,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    FaRequestCoordinator.instance.recordHttpStatus(
      statusCode: response.statusCode,
      responseBody: response.statusCode == 403 ? response.data : null,
    );
  }
}

Future<void> markBackgroundNoteAsUnread(Message message) {
  return BackgroundNoteUnreadService().markAsUnread(message);
}
