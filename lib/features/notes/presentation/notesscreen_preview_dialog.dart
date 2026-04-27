import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/shared/utils/fa_link_handler.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';

/// Dialog content for previewing a note/message.
class PreviewDialogContent extends StatefulWidget {
  final Message message;
  final String folder;
  final VoidCallback? onMarkedUnread;

  const PreviewDialogContent({
    Key? key,
    required this.message,
    required this.folder,
    this.onMarkedUnread,
  }) : super(key: key);

  @override
  _PreviewDialogContentState createState() => _PreviewDialogContentState();
}

class _PreviewDialogContentState extends State<PreviewDialogContent> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
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
  String senderLink = '';
  String senderUsername = '';
  int pageNumber = 1;
  bool _isClassic = false;

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
      return status != null && status >= 200 && status < 400;
    };
  }

  Future<void> _loadCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final cookies = <Cookie>[];
    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));
    cookies.add(Cookie('folder', widget.folder));
    final uri = Uri.parse('https://www.furaffinity.net');
    _cookieJar.saveFromResponse(
      uri,
      await FaCookieHelper.addCfClearanceCookie(cookies),
    );
  }

  Future<void> _fetchMessageDetails() async {
    try {
      await _loadCookies();
      final response = await _dio.get(
        'https://www.furaffinity.net${widget.message.link}',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            HttpHeaders.connectionHeader: 'close',
          },
        ),
      );

      if (response.statusCode == 200) {
        final decodedBody = response.data;
        final document = html_parser.parse(decodedBody);

        _isClassic = document.querySelector(
              'body[data-static-path="/themes/classic"][id="pageid-messagecenter-pms-view"]',
            ) !=
            null;

        // Extract message ID based on the page style.
        if (_isClassic) {
          final match = RegExp(r'/viewmessage/(\d+)/').firstMatch(widget.message.link);
          if (match != null) {
            messageId = match.group(1);
            pageNumber = 1;
          } else {
            throw Exception("Message ID could not be extracted from classic URL.");
          }
        } else {
          final match = RegExp(r'/msg/pms/(\d+)/(\d+)/').firstMatch(widget.message.link);
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

        document
            .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
            .forEach((e) => e.remove());

        String? tempSenderLink = document
                .querySelector('.message-center-note-information .addresses a')
                ?.attributes['href'] ??
            document
                .querySelector('div.message-center-note-information.addresses a')
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

          if (_isClassic) {
            final classicRecipientBlocks =
                document.querySelectorAll('span[style*="color: #999999"] .c-usernameBlock');
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
            final addresses = document
                .querySelectorAll('.message-center-note-information .addresses .c-usernameBlock');
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
          avatarUrl =
              document.querySelector('.message-center-note-information.avatar img')?.attributes['src'] ??
                  '';

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
            modernElem.querySelectorAll('.noteWarningMessage.noteWarningMessage--scam').forEach((e) => e.remove());
            modernHtml = modernElem.innerHtml;
          }
          if (classicElem != null) {
            classicElem.querySelectorAll('.noteWarningMessage.noteWarningMessage--scam').forEach((e) => e.remove());
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

        if (widget.onMarkedUnread != null) {
          widget.onMarkedUnread!();
        }
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

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE09321),),
            ),
            SizedBox(width: 12),
            Text(
              'Loading...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          errorMessage,
          style: const TextStyle(color: Colors.red, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!_isClassic)
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
                  Expanded(
                    child: Column(
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
              if (messageContentHtml.isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      selectionColor: const Color(0xFFE09321).withOpacity(0.4),
                      selectionHandleColor: const Color(0xFFE09321),
                    ),
                  ),
                  child: SelectionArea(
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
                  ),
                )
              else
                SelectableLinkify(
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
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.folder != 'sent') const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE09321),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
