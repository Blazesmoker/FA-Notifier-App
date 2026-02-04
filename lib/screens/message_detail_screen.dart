import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import '../main.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'note_reply_screen.dart';
import '../utils/fa_link_handler.dart';
import '../utils/utils.dart';
import '../services/fa_http.dart';

class MessageDetailScreen extends StatefulWidget {
  final String messageLink;
  final String folder;

  const MessageDetailScreen({
    Key? key,
    required this.messageLink,
    required this.folder,
  }) : super(key: key);

  @override
  _MessageDetailScreenState createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
  final _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock),
  );
  late Dio _dio;
  final CookieJar _cookieJar = CookieJar();

  bool isLoading = true;
  String errorMessage = '';
  String subject = '';
  String sender = '';
  String recipient = '';
  String sentDate = '';
  String avatarUrl = '';
  String messageContent = '';
  String messageContentHtml = '';
  String? messageId;
  String senderUsername = '';
  String senderLink = '';
  int pageNumber = 1;
  bool isClassic = false;
  bool _shouldShowReplySuccess = false;

  @override
  void initState() {
    super.initState();
    _initializeDio();
    _fetchMessageDetails();
  }

  void _initializeDio() {
    _dio = Dio();
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.options.headers['User-Agent'] = FAHttp.userAgent;
    _dio.options.followRedirects = true;
    _dio.options.validateStatus = (status) {
      return status != null && (status >= 200 && status < 400);
    };
  }

  Future<void> _loadCookies() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    List<Cookie> cookies = [];
    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));
    cookies.add(Cookie('folder', widget.folder));

    Uri uri = Uri.parse('https://www.furaffinity.net');
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
            'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/'
                'webp,image/apng,*/*;q=0.8',
            'Accept-Encoding': 'gzip, deflate, br, zstd',
            'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
          },
        ),
      );

      if (response.statusCode == 302) {
        setState(() {
          errorMessage = 'Redirected. Possibly authentication issues.';
          isLoading = false;
        });
        return;
      }

      if (response.statusCode == 200) {
        final decodedBody = response.data;
        final document = html_parser.parse(decodedBody);

        isClassic = document.querySelector(
            'body[data-static-path="/themes/classic"][id="pageid-messagecenter-pms-view"]'
        ) != null;

        // Extract message ID based on the page style.
        if (isClassic) {
          // Classic URL looks like: https://www.furaffinity.net/viewmessage/123456789/
          final match = RegExp(r'/viewmessage/(\d+)/').firstMatch(widget.messageLink);
          if (match != null) {
            messageId = match.group(1);
            pageNumber = 1; // Classic pages don't have a page number
          } else {
            throw Exception("Message ID could not be extracted from classic URL.");
          }
        } else {
          // Modern style: https://www.furaffinity.net/msg/pms/1/123456789/#message
          final match = RegExp(r'/msg/pms/(\d+)/(\d+)/').firstMatch(widget.messageLink);
          if (match != null) {
            pageNumber = int.parse(match.group(1)!);
            messageId = match.group(2);
          } else {
            throw Exception("Message ID could not be extracted from modern URL.");
          }
        }

        if (messageId == null || messageId!.isEmpty) {
          throw Exception("Message ID could not be extracted.");
        }

        // Removes the scam/warning block
        document
            .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
            .forEach((e) => e.remove());

        // Extracting the sender link
        String? tempSenderLink = document
            .querySelector('.message-center-note-information .addresses a')
            ?.attributes['href'] ??
            document
                .querySelector('div.message-center-note-information.addresses a')
                ?.attributes['href'];
        tempSenderLink ??= document
            .querySelector(
            'td.noteContent.alt1 span[style*="color: #999999"] '
                '.c-usernameBlock a[href^="/user/"]'
        )
            ?.attributes['href'];

        setState(() {
          subject = document.querySelector('#message h2')?.text.trim() ??
              document.querySelector('td.cat font b')?.text.trim() ??
              'No subject';

          sender = document
              .querySelector('.message-center-note-information .addresses a')
              ?.text
              .trim() ??
              document
                  .querySelector(
                  'a.c-usernameBlock__displayName.js-displayName-block span.js-displayName')
                  ?.text
                  .trim() ??
              'Unknown sender';

          // figures out recipient
          if (isClassic) {
            // In the old layout, the recipients are in <span style="color:#999999"> blocks
            final classicRecipientBlocks = document
                .querySelectorAll('span[style*="color: #999999"] .c-usernameBlock');
            if (classicRecipientBlocks.length > 1) {
              recipient = classicRecipientBlocks[1]
                  .querySelector('span.js-displayName')
                  ?.text
                  .trim() ??
                  'Unknown recipient';
            } else {
              recipient = 'Unknown recipient';
            }
          } else {
            // Modern layout
            final addresses =
            document.querySelectorAll('.message-center-note-information .addresses .c-usernameBlock');
            if (addresses.length > 1) {
              recipient = addresses[1]
                  .querySelector('.c-usernameBlock__displayName')
                  ?.text
                  .trim() ??
                  'Unknown recipient';
            } else {
              recipient = 'Unknown recipient';
            }
          }

          sentDate = document.querySelector('.popup_date')?.attributes['title'] ?? 'Unknown date';

          avatarUrl = document
              .querySelector('.message-center-note-information.avatar img')
              ?.attributes['src'] ??
              '';

          // If got a link for the sender, parses out the username
          if (tempSenderLink != null && tempSenderLink.isNotEmpty) {
            senderLink = tempSenderLink;
            senderUsername = Uri.parse(tempSenderLink).pathSegments.length >= 2
                ? Uri.parse(tempSenderLink).pathSegments[1]
                : 'Unknown';
          } else {
            senderUsername = 'Unknown';
          }


          final modernElem = document.querySelector('.section-body .user-submitted-links');
          final classicElem = document.querySelector('td.noteContent.alt1');

          String? modernHtml;
          String? classicHtml;
          if (modernElem != null) {
            modernHtml = modernElem.innerHtml;
          }
          if (classicElem != null) {

            classicElem.querySelector('span[style*="color: #999999"]')?.remove();
            classicHtml = classicElem.innerHtml;
          }


          final rawHtml = modernHtml ?? classicHtml;
          if (rawHtml == null || rawHtml.isEmpty) {
            messageContent = 'No content';
            messageContentHtml = '';
          } else {
            final innerDoc = html_parser.parse(rawHtml);
            innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
              final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
              if (fullLink != null) {
                anchor.innerHtml = fullLink;
              }
            });
            final updatedText = innerDoc.body?.text.trim() ?? '';
            messageContent = updatedText.isNotEmpty ? updatedText : 'No content';
            String fixedHtml = innerDoc.body?.innerHtml ?? rawHtml;
            fixedHtml = fixedHtml.replaceAllMapped(
              RegExp(r'src="(//[^"]+)"|href="(//[^"]+)"'),
              (m) {
                final url = m.group(1) ?? m.group(2);
                return url != null ? m[0]!.replaceFirst('//', 'https://') : m[0]!;
              },
            );
            messageContentHtml = fixedHtml;
          }

          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to fetch message: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
        isLoading = false;
      });
    }
  }


  Future<void> _markAsUnread() async {
    if (messageId == null) return;
    try {
      await _loadCookies();

      Map<String, dynamic> formData = {
        'manage_notes': '1',
        'items[]': messageId!,
        'move_to': 'unread',
      };

      final response = await _dio.post(
        'https://www.furaffinity.net/msg/pms/$pageNumber/$messageId/',
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
            return status != null && (status >= 200 && status < 400 || status == 302);
          },
        ),
      );

      if (response.statusCode == 302 || response.statusCode == 200) {
        showAppSnackBar(context, 'Message marked as unread');
        Navigator.pop(context, 'marked_unread');
      } else {
        setState(() {
          errorMessage = 'Failed to mark as unread: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  GlobalKey _selectableKey = GlobalKey();

  void _clearSelection() {
    setState(() {
      // Generates a new key to force the selectable widget to rebuild without a selection.
      _selectableKey = GlobalKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldShowReplySuccess) {
      _shouldShowReplySuccess = false; // Reset immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint('DEBUG: Showing snackbar from build cycle');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reply sent successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (TapDownDetails details) {
        final RenderBox? renderBox = _selectableKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          // Convert the global tap position to local coordinates of the selectable widget.
          final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
          // If the tap is outside the selectable widget’s bounds, clear the selection.
          if (!renderBox.size.contains(localPosition)) {
            _clearSelection();
          }
        } else {
          _clearSelection();
        }
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;
          Navigator.of(context).pop('refresh');
        },
        child: SafeArea(
          top: false,
          child: Scaffold(
            appBar: AppBar(
              title: Text(subject),
              backgroundColor: Colors.black,
            ),
            backgroundColor: Colors.black,
            body: isLoading
                ? const Center(
              child: PulsatingLoadingIndicator(
                size: 108.0,
                assetPath: 'assets/icons/fathemed.png',
              ),
            )
                : errorMessage.isNotEmpty
                ? Center(
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            )
                : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!isClassic)
                        GestureDetector(
                          onTap: () {
                            if (senderLink.isNotEmpty) {
                              handleFALink(context, senderLink);
                            }
                          },
                          child: Container(
                            width: 60,
                            height: 60,
                            color: Colors.transparent,
                            child: Image.network(
                              'https:$avatarUrl',
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              errorBuilder: (context, error, stackTrace) {
                                return Transform.scale(
                                  scale: 1.05,
                                  child: Image.asset(
                                    'assets/images/defaultpic.gif',
                                    fit: BoxFit.cover,
                                  ),
                                );
                              },
                            ),

                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      const SizedBox(width: 16),
                      Expanded(child:
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Sent by: ',
                                style: TextStyle(fontSize: 16, color: Colors.white),
                              ),
                              InkWell(
                                onTap: senderLink.isNotEmpty
                                    ? () => handleFALink(context, senderLink)
                                    : null,
                                child: Text(
                                  sender.isNotEmpty ? sender : 'Unknown sender',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFFE09321),
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'To: $recipient',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Date: $sentDate',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ),

                        ],
                      ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, thickness: 1, color: Colors.white54),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          textSelectionTheme: TextSelectionThemeData(
                            selectionColor: Color(0xFFE09321).withOpacity(0.4),
                            selectionHandleColor: Color(0xFFE09321),
                          ),
                        ),
                        child: messageContentHtml.isNotEmpty
                            ? SelectionArea(
                                key: _selectableKey,
                                child: html_pkg.Html(
                                  data: messageContentHtml,
                                  style: {
                                    'body': html_pkg.Style(
                                      margin: html_pkg.Margins.zero,
                                      padding: html_pkg.HtmlPaddings.zero,
                                      color: Colors.white,
                                      fontSize: html_pkg.FontSize(16),
                                    ),
                                    'b': html_pkg.Style(fontWeight: FontWeight.bold),
                                    'strong': html_pkg.Style(fontWeight: FontWeight.bold),
                                    'i': html_pkg.Style(fontStyle: FontStyle.italic),
                                    '.bbcode_i': html_pkg.Style(fontStyle: FontStyle.italic),
                                    'u': html_pkg.Style(textDecoration: TextDecoration.underline),
                                    '.bbcode_u': html_pkg.Style(textDecoration: TextDecoration.underline),
                                    '.bbcode_center': html_pkg.Style(
                                      display: html_pkg.Display.block,
                                      textAlign: TextAlign.center,
                                    ),
                                    '.bbcode_left': html_pkg.Style(
                                      display: html_pkg.Display.block,
                                      textAlign: TextAlign.left,
                                    ),
                                    '.bbcode_right': html_pkg.Style(
                                      display: html_pkg.Display.block,
                                      textAlign: TextAlign.right,
                                    ),
                                    'a': html_pkg.Style(
                                      color: const Color(0xFFE09321),
                                      textDecoration: TextDecoration.none,
                                    ),
                                  },
                                  onLinkTap: (url, _, __) {
                                    if (url != null) handleFALink(context, url);
                                  },
                                ),
                              )
                            : SelectableLinkify(
                                key: _selectableKey,
                                onOpen: (link) async {
                                  await handleFALink(context, link.url);
                                },
                                text: messageContent,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                                linkStyle: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFE09321),
                                  decoration: TextDecoration.none,
                                  decorationColor: Color(0xFFE09321),
                                ),
                                selectionControls: MaterialTextSelectionControls(),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.folder != 'sent')
                        OutlinedButton(
                          onPressed: _markAsUnread,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE09321),
                            side: const BorderSide(
                              color: Color(0xFFE09321),
                            ),
                          ),
                          child: const Text('Mark Unread'),
                        ),
                      if (widget.folder != 'sent') const SizedBox(width: 8),


                      if (widget.folder != 'sent')
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NoteReplyScreen(
                                  subject: subject,
                                  originalContent: messageContent,
                                  originalContentHtml: messageContentHtml.isNotEmpty ? messageContentHtml : null,
                                  username: senderUsername,
                                  messageId: messageId ?? '',
                                  messageLink: widget.messageLink,
                                ),
                              ),
                            ).then((result) {
                              if (result == true) {
                                rootMessengerKey.currentState?.showSnackBar(
                                  const SnackBar(
                                    content: Text('Reply sent successfully!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE09321),
                          ),
                          child: const Text('Reply'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
