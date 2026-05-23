import 'dart:io';

import 'package:FANotifier/features/submissions/data/finalize_submission_parser.dart';
import 'package:FANotifier/features/submissions/domain/finalize_submission_options.dart';
import 'package:FANotifier/features/submissions/domain/finalize_submission_request.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FinalizeSubmissionService {
  FinalizeSubmissionService({
    required FlutterSecureStorage secureStorage,
  })  : _secureStorage = secureStorage,
        _dio = Dio(),
        _cookieJar = CookieJar() {
    _initializeDio();
  }

  final FlutterSecureStorage _secureStorage;
  final Dio _dio;
  final CookieJar _cookieJar;

  void _initializeDio() {
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.headers['Accept'] =
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';
    _dio.options.headers['Accept-Encoding'] = 'gzip, deflate, br, zstd';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9';
    _dio.options.followRedirects = true;
    _dio.options.validateStatus = (status) {
      return status != null && (status >= 200 && status < 400);
    };

    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  Future<FinalizeSubmissionOptions> fetchOptions() async {
    await _loadCookies();

    final response = await _dio.get(
      'https://www.furaffinity.net/submit/finalize/',
    );

    debugPrint("GET /submit/finalize/ Status Code: ${response.statusCode}");

    await _saveToFile(
      'fetch_options_get.txt',
      'Request: GET /submit/finalize/\nResponse: ${response.data}\nTimestamp: ${DateTime.now()}\n\n',
    );

    if (response.data is String && response.data.length > 1000) {
      debugPrint("Response snippet: ${response.data.substring(0, 1000)}");
    } else {
      debugPrint("Response data: ${response.data}");
    }

    if (response.statusCode == 200 || response.statusCode == 302) {
      return parseFinalizeSubmissionOptions(response.data as String);
    }

    throw Exception(
      'Failed to load submission finalization page. Status code: ${response.statusCode}',
    );
  }

  Future<void> finalizeSubmission(FinalizeSubmissionRequest request) async {
    final data = request.toFormData();

    debugPrint("Finalizing submission with key: ${data['key']}");
    debugPrint("Finalizing submission with data: $data");

    await _saveToFile(
      'finalize_submission_post.txt',
      'Request Data: $data\nTimestamp: ${DateTime.now()}\n\n',
    );

    final response = await _dio.post(
      'https://www.furaffinity.net/submit/finalize/',
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Referer': 'https://www.furaffinity.net/submit/finalize/',
        },
        followRedirects: false,
        validateStatus: (status) {
          return status != null && (status >= 200 && status < 400);
        },
      ),
    );

    debugPrint("POST /submit/finalize/ Status Code: ${response.statusCode}");
    debugPrint("Response Headers: ${response.headers.map}");

    var responseBody = '';
    if (response.data is String) {
      responseBody = response.data;
      const chunkSize = 1000;
      for (int i = 0; i < responseBody.length; i += chunkSize) {
        final end = (i + chunkSize < responseBody.length)
            ? i + chunkSize
            : responseBody.length;
        debugPrint("Response Body Chunk: ${responseBody.substring(i, end)}");
      }
    } else {
      debugPrint("Response Data: ${response.data}");
    }

    if (response.statusCode == 302) {
      final location = response.headers.value('location');
      debugPrint("Redirect Location: $location");

      if (location != null && location.contains('?upload-successful')) {
        return;
      }
      throw Exception('Upload failed: Unexpected redirect location.');
    }

    if (response.statusCode == 200) {
      if (responseBody.contains('?upload-successful')) {
        return;
      }
      final errorMessage = parseFinalizeSubmissionErrorMessage(responseBody);
      throw Exception('Upload failed: $errorMessage');
    }

    throw Exception("Upload failed with status code: ${response.statusCode}");
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

    final prefs = await SharedPreferences.getInstance();
    final sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    final sfwValue = sfwEnabled ? '1' : '0';

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
    cookies.add(Cookie('sfw', sfwValue));

    final uri = Uri.parse('https://www.furaffinity.net');
    await _cookieJar.saveFromResponse(
      uri,
      await FaCookieHelper.addCfClearanceCookie(cookies),
    );

    final savedCookies = await _cookieJar.loadForRequest(uri);
    for (var cookie in savedCookies) {
      debugPrint(cookie.name);
    }
  }

  Future<void> _saveToFile(String fileName, String content) async {
    try {
      final directory = await Directory.systemTemp.createTemp('request_logs');
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content, mode: FileMode.append);
      debugPrint('Saved request body to file: ${file.path}');
    } catch (e) {
      debugPrint('Error saving to file: $e');
    }
  }
}
