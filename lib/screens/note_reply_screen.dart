import 'dart:io';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../utils.dart';
import '../widgets/PulsatingLoadingIndicator.dart';

class NoteReplyScreen extends StatefulWidget {
  final String subject;
  final String originalContent;
  final String username;
  final String messageId;
  final String messageLink;

  const NoteReplyScreen({
    Key? key,
    required this.subject,
    required this.originalContent,
    required this.username,
    required this.messageId,
    required this.messageLink,
  }) : super(key: key);

  @override
  _NoteReplyScreenState createState() => _NoteReplyScreenState();
}

class _NoteReplyScreenState extends State<NoteReplyScreen> {
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;
  bool _useWebView = false;
  bool _isClassicTheme = false;

  late Dio _dio;
  final CookieJar _cookieJar = CookieJar();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String recipient = 'Loading...';
  bool _isMessageDetailsLoading = true;
  String errorMessage = '';

  WebViewController? _webViewController;
  bool _isWebViewInitialized = false;

  bool _showCloudflareMessage = true;

  @override
  void initState() {
    super.initState();
    _initializeDio();
    _fetchMessageDetails();
  }

  void _initializeDio() {
    _dio = Dio();
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/130.0.0.0 Safari/537.36';
    _dio.options.followRedirects = false;
    _dio.options.validateStatus = (status) =>
    status != null && status >= 200 && status < 400;
  }

  Future<void> _loadCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final cookies = <Cookie>[];
    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));

    final uri = Uri.parse('https://www.furaffinity.net');
    _cookieJar.saveFromResponse(uri, cookies);
  }

  Future<void> _fetchMessageDetails() async {
    try {
      await _loadCookies();
      final response = await _dio.get(
        'https://www.furaffinity.net${widget.messageLink}',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          },
        ),
      );

      if (response.statusCode == 200) {
        final doc = html_parser.parse(response.data);

        _isClassicTheme = doc.querySelector(
            'body[data-static-path="/themes/classic"][id="pageid-messagecenter-pms-view"]') !=
            null;

        if (_isClassicTheme) {
          final classicSpan = doc.querySelector('span[style*="color: #999999"]');
          if (classicSpan != null) {
            final userNameAnchors = classicSpan.querySelectorAll(
                'a.c-usernameBlock__userName.js-userName-block');
            if (userNameAnchors.isNotEmpty) {
              final senderAnchor = userNameAnchors.first;
              final href = senderAnchor.attributes['href'] ?? '';
              final parts = href.split('/');
              if (parts.length >= 3) {
                recipient = parts[2];
              }
            }

            if (recipient == 'Loading...') {
              final displayNameAnchors = classicSpan.querySelectorAll(
                  'a.c-usernameBlock__displayName.js-displayName-block');
              if (displayNameAnchors.isNotEmpty) {
                final senderAnchor = displayNameAnchors.first;
                final href = senderAnchor.attributes['href'] ?? '';
                final parts = href.split('/');
                if (parts.length >= 3) {
                  recipient = parts[2];
                }
              }
            }
          }
          if (recipient == 'Loading...') {
            recipient = 'UnknownRecipient';
          }
        } else {
          recipient = (doc
              .querySelector('.message-center-note-information .addresses a:last-child')
              ?.text
              .trim() ??
              'Unknown recipient')
              .replaceFirst(RegExp(r'^.'), '');

          if (recipient == 'Loading...') {
            recipient = 'UnknownRecipient';
          }
        }

        setState(() {
          _isMessageDetailsLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to fetch details: status ${response.statusCode}';
          _isMessageDetailsLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error fetching details: $e';
        _isMessageDetailsLoading = false;
      });
    }
  }

  Future<void> _initializeWebView() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      setState(() {
        errorMessage = 'Not logged in or missing cookies.';
        _useWebView = false;
      });
      return;
    }

    final webViewUrl = 'https://www.furaffinity.net${widget.messageLink}';

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller = WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
          },
          onPageFinished: (String url) async {
            await _injectFormHandler(controller);
            setState(() {
              _isWebViewInitialized = true;
            });

            if (url.contains('/msg/pms/') && !url.contains('/viewmessage/') && !url.contains('#message')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Reply sent successfully!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
              Navigator.pop(context, true);
            }
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              errorMessage = 'WebView error: ${error.description}';
            });
          },
        ),
      )
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
      );

    final cookieManager = WebViewCookieManager();
    await cookieManager.setCookie(
      WebViewCookie(
        name: 'a',
        value: cookieA,
        domain: '.furaffinity.net',
        path: '/',
      ),
    );
    await cookieManager.setCookie(
      WebViewCookie(
        name: 'b',
        value: cookieB,
        domain: '.furaffinity.net',
        path: '/',
      ),
    );

    await controller.loadRequest(Uri.parse(webViewUrl));

    setState(() {
      _webViewController = controller;
    });
  }

  Future<void> _injectFormHandler(WebViewController controller) async {
    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) return;

    final fullMessage = '$replyText\n\n—————————\n${widget.originalContent}';
    final escapedMessage = fullMessage
        .replaceAll('\\', '\\\\')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\'', '\\\'')
        .replaceAll('"', '\\"');

    final js = '''
      (function() {
        // Added viewport meta tag for better mobile zoom control
        var viewport = document.querySelector('meta[name="viewport"]');
        if (!viewport) {
          viewport = document.createElement('meta');
          viewport.name = 'viewport';
          document.head.appendChild(viewport);
        }
        viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes';
        
        // Waits a bit for the form to be fully loaded
        setTimeout(function() {
          // Fills in the form fields
          var toField = document.querySelector('input[name="to"]');
          var subjectField = document.querySelector('input[name="subject"]');
          var messageField = document.querySelector('textarea[name="message"]');
          
          if (toField) toField.value = '$recipient';
          if (subjectField) subjectField.value = '${widget.subject}';
          if (messageField) messageField.value = '$escapedMessage';
          
       
          var style = document.createElement('style');
          style.innerHTML = `
            .block-menu-top, .block-banners, .footer, 
            .headerAds, .leaderboardAd, .footerAds,
            table[cellpadding="10"]:first-of-type { display: none !important; }
            body { padding-top: 20px !important; }
            .maintable { margin-top: 0 !important; }
            .viewmessage .maintable:first-of-type { display: none !important; }
          `;
          document.head.appendChild(style);
          
          // Scroll to the reply form
          var noteForm = document.getElementById('note-form');
          if (noteForm) {
            noteForm.scrollIntoView({ behavior: 'smooth' });
          }
        }, 500);
      })();
    ''';

    await controller.runJavaScript(js);
  }

  Future<void> _sendReplyModern() async {
    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reply cannot be empty.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
      errorMessage = '';
    });

    try {
      await _loadCookies();
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('Not logged in or missing cookies.');
      }

      String msgId;
      int pageNo;
      if (widget.messageLink.contains('/viewmessage/')) {
        final match = RegExp(r'/viewmessage/(\d+)/').firstMatch(widget.messageLink);
        if (match != null) {
          msgId = match.group(1)!;
          pageNo = 1;
        } else {
          throw Exception('Invalid message ID from link: ${widget.messageLink}');
        }
      } else {
        pageNo = extractPageNumber(widget.messageLink);
        msgId = extractMessageId(widget.messageLink);
        if (msgId.isEmpty) {
          throw Exception('Invalid message ID from link: ${widget.messageLink}');
        }
      }

      final getUrl = 'https://www.furaffinity.net/msg/pms/$pageNo/$msgId/#message';
      final getResp = await _dio.get(
        getUrl,
        options: Options(
          headers: {
            'Referer': getUrl,
            'Cookie': 'a=$cookieA; b=$cookieB',
          },
          followRedirects: false,
        ),
      );

      if (getResp.statusCode == 302) {
        throw Exception("GET request was redirected (auth issue?)");
      }

      final doc = html_parser.parse(getResp.data);
      final keyInput = doc.querySelector('form#note-form input[name="key"]');
      final keyValue = keyInput?.attributes['value'] ?? '';
      if (keyValue.isEmpty) {
        throw Exception("Failed to find the 'key' hidden field in the note form.");
      }

      final formData = {
        'key': keyValue,
        'to': recipient,
        'subject': widget.subject,
        'message': '$replyText\n\n—————————\n${widget.originalContent}',
      };
      final encodedFormData = Uri(queryParameters: formData).query;
      const sendMessageUrl = 'https://www.furaffinity.net/msg/send/';

      final postResp = await _dio.post(
        sendMessageUrl,
        data: encodedFormData,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://www.furaffinity.net',
            'Referer': getUrl,
            'Cookie': 'a=$cookieA; b=$cookieB',
          },
          followRedirects: false,
        ),
      );

      if (postResp.statusCode == 302) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply sent successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      } else {
        errorMessage = 'Failed to send reply: ${postResp.statusCode}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      errorMessage = 'Error sending reply: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _sendReply() async {
    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reply cannot be empty.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isClassicTheme) {
      setState(() {
        _useWebView = true;
        _isSending = true;
      });
      await _initializeWebView();
    } else {
      await _sendReplyModern();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isMessageDetailsLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Reply to Note"),
          backgroundColor: Colors.black,
        ),
        backgroundColor: Colors.black,
        body: const Center(
          child: PulsatingLoadingIndicator(
            size: 88.0,
            assetPath: 'assets/icons/fathemed.png',
          ),
        ),
      );
    }

    if (_useWebView && _webViewController != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _useWebView = false;
                _isSending = false;
              });
            },
          ),
          title: const Text("Complete Reply"),
          backgroundColor: Colors.black,
        ),
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            WebViewWidget(controller: _webViewController!),
            if (!_isWebViewInitialized)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  backgroundColor: Colors.grey[800],
                ),
              ),
            if (_showCloudflareMessage) 
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Complete the Cloudflare verification and click "Post" to send your reply.',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () {
                          setState(() {
                            _showCloudflareMessage = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text("Reply to Note"),
          actions: [
            IconButton(
              icon: _isSending
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2.0,
                ),
              )
                  : const Icon(Icons.send),
              onPressed: _isSending ? null : _sendReply,
            ),
          ],
        ),
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (errorMessage.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                errorMessage,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          if (_isClassicTheme)
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Cloudflare verification is required in Classic theme.',
                                      style: TextStyle(color: Colors.orange, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            'Recipient: $recipient',
                            style: const TextStyle(fontSize: 16, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Subject: ${widget.subject}',
                            style: const TextStyle(fontSize: 16, color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Original Note:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              widget.originalContent,
                              style: const TextStyle(fontSize: 16, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: TextField(
                              controller: _replyController,
                              style: const TextStyle(color: Colors.white),
                              minLines: 6,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Your Reply',
                                labelStyle: TextStyle(color: Colors.white),
                                alignLabelWithHint: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}