import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:FANotifier/features/profile/data/shout_form_parser.dart';
import 'package:FANotifier/features/profile/domain/post_shout_result.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

class ShoutService {
  ShoutService({required FlutterSecureStorage secureStorage})
      : _secureStorage = secureStorage;

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

  Future<void> _initialize() async {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) {
      return status != null && (status >= 200 && status < 400);
    };
    await _loadCookies();
    _initialized = true;
    _initializing = null;
  }

  void close() {
    _dio.close();
  }

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

      final response = await _dio.post(
        'https://www.furaffinity.net/user/$username/',
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

    final response = await _dio.get(
      'https://www.furaffinity.net/user/$username/',
      options: Options(
        headers: {
          'Referer': 'https://www.furaffinity.net/user/$username/',
          'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
            'a=$cookieA; b=$cookieB',
          ),
        },
      ),
    );

    if (response.statusCode == 302) throw Exception('Authentication required');

    return parseShoutKey(response.data);
  }
}
