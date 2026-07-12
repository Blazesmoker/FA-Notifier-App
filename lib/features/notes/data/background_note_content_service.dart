import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/features/notes/data/background_note_content_parser.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';

class BackgroundNoteContentService {
  BackgroundNoteContentService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  Future<String> fetchContent(String link) async {
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
    final url = 'https://www.furaffinity.net$link';
    await FaRequestCoordinator.instance.waitForTurn(label: 'GET $url');
    final response = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': FAHttp.userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    FaRequestCoordinator.instance.recordHttpStatus(
      statusCode: response.statusCode,
      responseBody: response.statusCode == 403 ? response.data : null,
    );
    if (response.statusCode == 200) {
      return parseBackgroundNoteContent(response.data);
    }
    throw Exception('HTTP ${response.statusCode}');
  }
}

Future<String> fetchBackgroundNoteContent(String link) {
  return BackgroundNoteContentService().fetchContent(link);
}
