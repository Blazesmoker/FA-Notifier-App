import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PostShoutScreen extends StatefulWidget {
  final String username;

  const PostShoutScreen({Key? key, required this.username}) : super(key: key);

  @override
  _PostShoutScreenState createState() => _PostShoutScreenState();
}

class _PostShoutScreenState extends State<PostShoutScreen> {
  final TextEditingController _shoutController = TextEditingController();
  final Dio _dio = Dio();
  final CookieJar _cookieJar = CookieJar();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  int _currentLength = 0;
  final int _maxLength = 222;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeDio();
    _shoutController.addListener(() {
      setState(() {
        _currentLength = _shoutController.text.length;
      });
      if (_shoutController.text.length > _maxLength) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Too many characters!')),
        );
      }
    });
  }

  Future<void> _initializeDio() async {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) {
      return status != null && (status >= 200 && status < 400);
    };
    await _loadCookies();
  }

  Future<void> _loadCookies() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    List<Cookie> cookies = [];
    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));

    Uri uri = Uri.parse('https://www.furaffinity.net');
    await _cookieJar.saveFromResponse(uri, cookies);
  }

  Future<String?> _fetchShoutKey() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('Authentication cookies not found. Please log in again.');
    }

    final response = await _dio.get(
      'https://www.furaffinity.net/user/${widget.username}/',
      options: Options(
        headers: {
          'Referer': 'https://www.furaffinity.net/user/${widget.username}/',
          'Cookie': 'a=$cookieA; b=$cookieB',
        },
      ),
    );

    if (response.statusCode == 302) throw Exception('Authentication required');

    final document = html_parser.parse(response.data);
    // Modern (beta) layout selector.
    String? key = document
        .querySelector('form.shout-post-form input[name="key"]')
        ?.attributes['value'];
    // If the modern selector didn't return a key, fall back to the classic HTML layout.
    if (key == null) {
      key = document
          .querySelector('form#JSForm input[name="key"]')
          ?.attributes['value'];
    }
    return key;
  }


  Future<void> _postShout() async {
    // Check for empty shout
    if (_shoutController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a shout.')),
      );
      return;
    }
    // Check if text length exceeds the limit before posting.
    if (_shoutController.text.trim().length > _maxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot send more than 222 characters!')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final key = await _fetchShoutKey();

      if (key == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to retrieve shout key.')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

      if (cookieA == null || cookieB == null) {
        throw Exception('Authentication cookies not found. Please log in again.');
      }

      final formData = {
        'action': 'shout',
        'key': key,
        'name': widget.username,
        'shout': _shoutController.text.trim(),
      };

      String encodedFormData = Uri(queryParameters: formData).query;

      final response = await _dio.post(
        'https://www.furaffinity.net/user/${widget.username}/',
        data: encodedFormData,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://www.furaffinity.net',
            'Referer': 'https://www.furaffinity.net/user/${widget.username}/',
            'DNT': '1',
            'Cookie': 'a=$cookieA; b=$cookieB',
          },
          followRedirects: false,
        ),
      );

      if (response.statusCode == 302) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Shout posted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post shout: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _shoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Ensures the scaffold resizes when the keyboard appears.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Compose Shout"),
        actions: [
          _isLoading
              ? Padding(
            padding: const EdgeInsets.all(12.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          )
              : IconButton(
            icon: const Icon(Icons.send),
            onPressed: _postShout,
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          // Dismisses the keyboard when tapping outside.
          onTap: () => FocusScope.of(context).unfocus(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  // Allows the content to scroll when necessary.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _shoutController,
                              maxLines: null, // Allows the TextField to expand.
                              keyboardType: TextInputType.multiline,
                              // Limits the number of characters using inputFormatters.
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(_maxLength),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Your Shout',
                                border: const OutlineInputBorder(),
                                alignLabelWithHint: true,
                                // Display the character counter.
                                counterText: '$_currentLength/$_maxLength',
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
