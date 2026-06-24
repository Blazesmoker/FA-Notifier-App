import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/features/notes/data/note_form_parser.dart';
import 'package:FANotifier/features/notes/domain/new_message_send_result.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';
import 'package:FANotifier/shared/fa/fa_system_message_parser.dart';

class NewMessageService {
  NewMessageService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accountName: 'flutter_secure_storage_service',
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;
  final Dio _dio = Dio();
  final CookieJar _cookieJar = CookieJar();
  bool _initialized = false;
  Future<void>? _initializing;

  Future<void> initialize() async {
    if (_initialized) return;
    if (_initializing != null) {
      await _initializing;
      return;
    }
    _initializing = _initialize();
    try {
      await _initializing;
    } finally {
      if (!_initialized) {
        _initializing = null;
      }
    }
  }

  Future<NewMessageSendResult> sendMessage({
    required String recipient,
    required String subject,
    required String message,
  }) async {
    try {
      await initialize();
      final key = await _fetchKey();

      if (key == null) {
        return const NewMessageSendResult(
          success: false,
          message: 'Failed to retrieve message key.',
        );
      }

      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found. Please log in again.');
      }

      final formData = {
        'key': key,
        'to': recipient,
        'subject': subject,
        'message': message,
      };

      final encodedFormData = Uri(queryParameters: formData).query;

      await FaRequestCoordinator.instance.waitForTurn(
        label: 'POST https://www.furaffinity.net/msg/send/',
      );
      final response = await _dio.post(
        'https://www.furaffinity.net/msg/send/',
        data: encodedFormData,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://www.furaffinity.net',
            'Referer': 'https://www.furaffinity.net/msg/pms/',
            'DNT': '1',
            'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
              'a=$cookieA; b=$cookieB',
            ),
          },
          followRedirects: false,
        ),
      );

      FaRequestCoordinator.instance.recordHttpStatus(
        statusCode: response.statusCode,
        responseBody: response.statusCode == 403 ? response.data : null,
      );

      if (response.statusCode == 302) {
        return const NewMessageSendResult(
          success: true,
          message: 'Message sent successfully!',
        );
      }

      final faMessage = parseFaSystemMessage(response.data);
      if (faMessage != null) {
        if (faMessage.isMaintenanceOrUnavailable) {
          FaRequestCoordinator.instance.recordMaintenanceOrUnavailable(
            message: faMessage.message,
            retryAfter: faMessage.retryAfter,
          );
        }
        return NewMessageSendResult(
          success: false,
          message: faMessage.message,
          retryAfterSeconds: faMessage.retryAfter?.inSeconds,
        );
      }

      return NewMessageSendResult(
        success: false,
        message: 'Failed to send message: ${response.statusCode}',
      );
    } catch (e) {
      return NewMessageSendResult(
        success: false,
        message: 'Error: $e',
      );
    }
  }

  Future<void> _initialize() async {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.headers['Accept'] =
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';
    _dio.options.headers['Accept-Encoding'] = 'gzip, deflate, br, zstd';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9,ru;q=0.8';
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) {
      return status != null && status >= 200 && status < 600;
    };
    await _loadCookies();
    _initialized = true;
    _initializing = null;
  }

  Future<void> _loadCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final trackingConsent =
        await _secureStorage.read(key: '_tracking_consent');
    final shopifyY = await _secureStorage.read(key: '_shopify_y');
    final cc = await _secureStorage.read(key: 'cc');
    final n = await _secureStorage.read(key: 'n');
    final sz = await _secureStorage.read(key: 'sz');
    final folder = await _secureStorage.read(key: 'folder');

    final cookies = <Cookie>[];

    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));
    if (trackingConsent != null) {
      cookies.add(Cookie('_tracking_consent', trackingConsent));
    }
    if (shopifyY != null) cookies.add(Cookie('_shopify_y', shopifyY));
    if (cc != null) cookies.add(Cookie('cc', cc));
    if (n != null) cookies.add(Cookie('n', n));
    if (sz != null) cookies.add(Cookie('sz', sz));
    if (folder != null) cookies.add(Cookie('folder', folder));

    final uri = Uri.parse('https://www.furaffinity.net');
    await _cookieJar.saveFromResponse(
      uri,
      await FaCookieHelper.addCfClearanceCookie(cookies),
    );
  }

  Future<String?> _fetchKey() async {
    await _loadCookies();

    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('Authentication cookies not found. Please log in again.');
    }

    await FaRequestCoordinator.instance.waitForTurn(
      label: 'GET https://www.furaffinity.net/msg/pms/',
    );
    final response = await _dio.get(
      'https://www.furaffinity.net/msg/pms/',
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Referer': 'https://www.furaffinity.net/msg/pms/',
          'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
            'a=$cookieA; b=$cookieB',
          ),
        },
      ),
    );

    if (response.statusCode == 302) throw Exception('Authentication required');
    FaRequestCoordinator.instance.recordHttpStatus(
      statusCode: response.statusCode,
      responseBody: response.statusCode == 403 ? response.data : null,
    );

    return parseNewMessageKey(response.data);
  }
}
