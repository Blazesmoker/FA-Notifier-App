import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/features/notes/data/message_detail_parser.dart';
import 'package:FANotifier/features/notes/domain/note_message_models.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';

class NoteMessageService {
  NoteMessageService({
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

  Future<NoteMessageFetchResult> fetchMessageDetails({
    required String messageLink,
    required String folder,
    bool closeConnection = false,
  }) async {
    await _loadCookies(folder);
    final url = 'https://www.furaffinity.net$messageLink';
    await FaRequestCoordinator.instance.waitForTurn(label: 'GET $url');
    final response = await _dio.get(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Accept': closeConnection
              ? 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
              : 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/'
                  'webp,image/apng,*/*;q=0.8',
          if (closeConnection) HttpHeaders.connectionHeader: 'close',
          if (!closeConnection) 'Accept-Encoding': 'gzip, deflate, br, zstd',
          if (!closeConnection) 'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
        },
      ),
    );
    FaRequestCoordinator.instance.recordHttpStatus(
      statusCode: response.statusCode,
    );

    if (response.statusCode == 302) {
      return NoteMessageFetchResult(
        statusCode: response.statusCode,
        redirected: true,
      );
    }

    if (response.statusCode == 200) {
      return NoteMessageFetchResult(
        details: parseNoteMessageDetails(response.data, messageLink),
        statusCode: response.statusCode,
      );
    }

    return NoteMessageFetchResult(statusCode: response.statusCode);
  }

  Future<int?> markAsUnread({
    required String folder,
    required String messageId,
    required int pageNumber,
  }) async {
    await _loadCookies(folder);

    final formData = {
      'manage_notes': '1',
      'items[]': messageId,
      'move_to': 'unread',
    };

    final url = 'https://www.furaffinity.net/msg/pms/$pageNumber/$messageId/';
    await FaRequestCoordinator.instance.waitForTurn(label: 'POST $url');
    final response = await _dio.post(
      url,
      data: formData,
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': 'https://www.furaffinity.net/msg/pms/$pageNumber/$messageId/',
          'Origin': 'https://www.furaffinity.net',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,'
              'image/apng,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
          'Cache-Control': 'max-age=0',
          'DNT': '1',
          'Upgrade-Insecure-Requests': '1',
        },
        followRedirects: false,
        validateStatus: (status) {
          return status != null &&
              (status >= 200 && status < 400 || status == 302);
        },
      ),
    );
    FaRequestCoordinator.instance.recordHttpStatus(
      statusCode: response.statusCode,
    );

    return response.statusCode;
  }

  void _initializeDio() {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.followRedirects = true;
    _dio.options.validateStatus = (status) {
      return status != null && (status >= 200 && status < 400);
    };
  }

  Future<void> _loadCookies(String folder) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    final cookies = <Cookie>[];
    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));
    cookies.add(Cookie('folder', folder));

    final uri = Uri.parse('https://www.furaffinity.net');
    _cookieJar.saveFromResponse(
      uri,
      await FaCookieHelper.addCfClearanceCookie(cookies),
    );
  }
}
