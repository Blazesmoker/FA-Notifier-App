import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/core/fa/fa_cookie_helper.dart';
import 'package:FANotifier/core/network/fa_http.dart';
import 'package:FANotifier/core/network/fa_request_coordinator.dart';

class NoteUnreadService {
  NoteUnreadService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<void> markAsUnreadWithoutRefetch(Message msg) async {
    final msgId = msg.id;
    if (msgId.isEmpty) return;

    final pageNum = _extractPageNumber(msg.link);

    try {
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) return;

      final dio = Dio();
      final cookieJar = CookieJar();
      dio.interceptors.add(CookieManager(cookieJar));
      cookieJar.saveFromResponse(
        Uri.parse('https://www.furaffinity.net'),
        await FaCookieHelper.addCfClearanceCookie(
          [Cookie('a', cookieA), Cookie('b', cookieB)],
        ),
      );

      final formData = {
        'manage_notes': '1',
        'items[]': msgId,
        'move_to': 'unread',
      };

      final url = 'https://www.furaffinity.net/msg/pms/$pageNum/$msgId/';
      await FaRequestCoordinator.instance.waitForTurn(label: 'POST $url');
      final response = await dio.post(
        url,
        data: formData,
        options: Options(
          headers: {
            'User-Agent': FAHttp.userAgent,
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://www.furaffinity.net/msg/pms/$pageNum/$msgId/',
            'Origin': 'https://www.furaffinity.net',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
            HttpHeaders.connectionHeader: 'close',
            'Cache-Control': 'max-age=0',
            'DNT': '1',
            'Upgrade-Insecure-Requests': '1',
          },
          followRedirects: false,
          validateStatus: (s) =>
              s != null && s >= 200 && s < 600,
        ),
      );
      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        responseBody: response.statusCode == 403 ? response.data : null,
      );

      if (response.statusCode != 302 && response.statusCode != 200) {
        throw Exception('Failed to mark as unread: ${response.statusCode}');
      }
    } catch (_) {}
  }

  int _extractPageNumber(String link) {
    if (link.contains('/viewmessage/')) {
      return 1;
    }

    final match = RegExp(r'/msg/pms/(\d+)/(\d+)/').firstMatch(link);
    if (match != null) {
      return int.parse(match.group(1)!);
    }

    return 1;
  }
}
