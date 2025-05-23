import 'dart:io';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils.dart';
import '../widgets/PulsatingLoadingIndicator.dart';

class NoteReplyScreen extends StatefulWidget {
  final String subject;         // Title of the note
  final String originalContent; // Original text in the note
  final String username;        // The "from" user (or who we're replying to)
  final String messageId;       // ID of the note
  final String messageLink;     // Full path to the note (/viewmessage/xxx or /msg/pms/xxx/)

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

  late Dio _dio;
  final CookieJar _cookieJar = CookieJar();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();


  String recipient = 'Loading...';
  bool _isMessageDetailsLoading = true;
  String errorMessage = '';

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


        final bool isClassic = doc.querySelector(
            'body[data-static-path="/themes/classic"][id="pageid-messagecenter-pms-view"]'
        ) != null;
        print("classic: $isClassic");

        if (isClassic) {
          final classicSpan = doc.querySelector('span[style*="color: #999999"]');
          if (classicSpan != null) {
            // Looks for all display name anchors and picks the one that isn't the sender.
            final displayNameAnchors = classicSpan.querySelectorAll(
                'a.c-usernameBlock__displayName.js-displayName-block');
            if (displayNameAnchors.isNotEmpty) {
              for (final anchor in displayNameAnchors) {
                final href = anchor.attributes['href'] ?? '';
                if (!href.toLowerCase().contains(widget.username.toLowerCase())) {
                  final parts = href.split('/');
                  if (parts.length >= 3) {
                    recipient = parts[2];
                    print("recipient: $recipient");
                    break;
                  }
                }
              }
            }
          }
          if (recipient == 'Loading...') {
            recipient = 'UnknownRecipient';
          }
        } else {
          // For modern layout:
          recipient = (doc
              .querySelector('.message-center-note-information .addresses a:last-child')
              ?.text
              .trim() ?? 'Unknown recipient')
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

      // Extract message ID and page number for both classic and modern URLs.
      String msgId;
      int pageNo;
      if (widget.messageLink.contains('/viewmessage/')) {
        final match = RegExp(r'/viewmessage/(\d+)/').firstMatch(widget.messageLink);
        if (match != null) {
          msgId = match.group(1)!;
          pageNo = 1; // Classic pages don't have a page number.
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
        // A 302 redirect indicates success.
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

    return Scaffold(
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
                      if (errorMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            errorMessage,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Recipient: $recipient',
                                  style: const TextStyle(fontSize: 16, color: Colors.white),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Subject: ${widget.subject}',
                                  style: const TextStyle(fontSize: 16, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
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
    );
  }

}
