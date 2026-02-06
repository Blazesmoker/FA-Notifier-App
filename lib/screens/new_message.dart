import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/fa_http.dart';
import '../utils/bbcode_context_menu.dart';
import '../widgets/confirm_close_dialog.dart';

class NewMessageScreen extends StatelessWidget {
  final TextEditingController _recipientController;
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  NewMessageScreen({Key? key, String? recipient})
      : _recipientController = TextEditingController(text: recipient ?? ''),
        super(key: key);


  final _dio = Dio();
  final _cookieJar = CookieJar();
  final _secureStorage = const FlutterSecureStorage(iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock));

  Future<void> _initializeDio() async {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
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

    Uri uri = Uri.parse('https://www.furaffinity.net');
    await _cookieJar.saveFromResponse(uri, cookies);
  }

  Future<String?> _fetchKey() async {
    await _loadCookies();

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
          const SnackBar(
            content: Text('Message sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

  }

  @override
  Widget build(BuildContext context) {
    Future<void> onRequestClose() async {
      final confirmed = await ConfirmCloseDialog.show(context);
      if (confirmed && context.mounted) Navigator.pop(context);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) onRequestClose();
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onRequestClose,
        ),
        title: const Text("Compose New Message", overflow: TextOverflow.visible,),
        actions: [
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendMessage(context),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
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
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Recipient',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _subjectController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Subject',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          minLines: 6,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Your Message',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          contextMenuBuilder: BBCodeContextMenu.builder(_messageController),
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
    ));

  }

}
