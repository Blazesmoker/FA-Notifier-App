import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:fanotifier/features/profile/data/shout_form_parser.dart';
import 'package:fanotifier/features/profile/domain/post_shout_result.dart';
import 'package:fanotifier/features/profile/domain/profile_shout_repository.dart';
import 'package:fanotifier/core/fa/fa_cookie_helper.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/network/fa_request_coordinator.dart';

class ShoutService implements ProfileShoutRepository {
  ShoutService({
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

  @override
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

  Future<void> _initialize() async {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) {
      return status != null && status >= 200 && status < 600;
    };
    await _loadCookies();
    _initialized = true;
    _initializing = null;
  }

  @override
  void close() {
    _dio.close();
  }

  @override
  Future<PostShoutResult> postShout({
    required String username,
    required String shout,
  }) async {
    try {
      await initialize();
      final key = await _fetchShoutKey(username);

      if (key == null) {
        return const PostShoutResult(
          success: false,
          message: 'Failed to retrieve shout key.',
        );
      }

      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found. Please log in again.');
      }

      final formData = {
        'action': 'shout',
        'key': key,
        'name': username,
        'shout': shout,
      };

      final encodedFormData = Uri(queryParameters: formData).query;

      final url = 'https://www.furaffinity.net/user/$username/';
      await FaRequestCoordinator.instance.waitForTurn(label: 'POST $url');
      final response = await _dio.post(
        url,
        data: encodedFormData,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://www.furaffinity.net',
            'Referer': 'https://www.furaffinity.net/user/$username/',
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
        return const PostShoutResult(
          success: true,
          message: 'Shout posted successfully!',
          isError: false,
        );
      }

      return PostShoutResult(
        success: false,
        message: 'Failed to post shout: ${response.statusCode}',
      );
    } catch (e) {
      return PostShoutResult(
        success: false,
        message: 'Error: $e',
        isError: false,
      );
    }
  }

  Future<void> _loadCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    final cookies = <Cookie>[];
    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));

    final uri = Uri.parse('https://www.furaffinity.net');
    await _cookieJar.saveFromResponse(
      uri,
      await FaCookieHelper.addCfClearanceCookie(cookies),
    );
  }

  Future<String?> _fetchShoutKey(String username) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('Authentication cookies not found. Please log in again.');
    }

    final url = 'https://www.furaffinity.net/user/$username/';
    await FaRequestCoordinator.instance.waitForTurn(label: 'GET $url');
    final response = await _dio.get(
      url,
      options: Options(
        headers: {
          'Referer': 'https://www.furaffinity.net/user/$username/',
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

    if (response.statusCode == 302) throw Exception('Authentication required');

    return parseShoutKey(response.data);
  }
}
