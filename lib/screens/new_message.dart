import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NewMessageScreen extends StatelessWidget {
  final TextEditingController _recipientController;
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  NewMessageScreen({Key? key, String? recipient})
      : _recipientController = TextEditingController(text: recipient ?? ''),
        super(key: key);


  final _dio = Dio();
  final _cookieJar = CookieJar();
  final _secureStorage = const FlutterSecureStorage();

  Future<void> _initializeDio() async {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
    _dio.options.headers['Accept'] =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';
    _dio.options.headers['Accept-Encoding'] = 'gzip, deflate, br, zstd';
    _dio.options.headers['Accept-Language'] = 'en-US,en;q=0.9,ru;q=0.8';
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) {
      return status != null && (status >= 200 && status < 400);
    };
  }

  Future<void> _loadCookies() async {
    // Read all relevant cookies from secure storage
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    String? trackingConsent =
    await _secureStorage.read(key: '_tracking_consent');
    String? shopifyY = await _secureStorage.read(key: '_shopify_y');
    String? cc = await _secureStorage.read(key: 'cc');
    String? n = await _secureStorage.read(key: 'n');
    String? sz = await _secureStorage.read(key: 'sz');
    String? folder = await _secureStorage.read(key: 'folder');

    // Build a list of cookies
    List<Cookie> cookies = [];

    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));
    if (trackingConsent != null)
      cookies.add(Cookie('_tracking_consent', trackingConsent));
    if (shopifyY != null) cookies.add(Cookie('_shopify_y', shopifyY));
    if (cc != null) cookies.add(Cookie('cc', cc));
    if (n != null) cookies.add(Cookie('n', n));
    if (sz != null) cookies.add(Cookie('sz', sz));
    if (folder != null) cookies.add(Cookie('folder', folder));

    // Set cookies for the Fur Affinity domain
    Uri uri = Uri.parse('https://www.furaffinity.net');
    await _cookieJar.saveFromResponse(uri, cookies);
  }

  Future<String?> _fetchKey() async {
    await _loadCookies();

    // Retrieve cookies `a` and `b`
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('Authentication cookies not found. Please log in again.');
    }

    final response = await _dio.get(
      'https://www.furaffinity.net/msg/pms/',
      options: Options(
        headers: {
          'Referer': 'https://www.furaffinity.net/msg/pms/',
          'Cookie': 'a=$cookieA; b=$cookieB',
        },
      ),
    );

    if (response.statusCode == 302) throw Exception('Authentication required');

    final document = html_parser.parse(response.data);
    return document.querySelector('form#note-form input[name="key"]')?.attributes['value'];
  }

  Future<void> _sendMessage(BuildContext context) async {
    await _initializeDio();
    final key = await _fetchKey();

    if (key == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to retrieve message key.')),
      );
      return;
    }

    // Retrieve cookies `a` and `b`
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('Authentication cookies not found. Please log in again.');
    }

    final formData = {
      'key': key,
      'to': _recipientController.text.trim(),
      'subject': _subjectController.text.trim(),
      'message': _messageController.text.trim(),
    };

    // Encode form data as application/x-www-form-urlencoded
    String encodedFormData = Uri(queryParameters: formData).query;

    try {
      final response = await _dio.post(
        'https://www.furaffinity.net/msg/send/',
        data: encodedFormData,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://www.furaffinity.net',
            'Referer': 'https://www.furaffinity.net/msg/pms/',
            'DNT': '1',
            'Cookie': 'a=$cookieA; b=$cookieB',
          },
          followRedirects: false,
        ),
      );

      if (response.statusCode == 302) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent successfully!')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Compose New Message", overflow: TextOverflow.visible,),
        actions: [
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendMessage(context),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true, // Adjust content when the keyboard is visible
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _recipientController,
                        decoration: const InputDecoration(
                          labelText: 'Recipient',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Subject',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          maxLines: null, // Allows dynamic height
                          keyboardType: TextInputType.multiline,
                          decoration: const InputDecoration(
                            labelText: 'Your Message',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

}
