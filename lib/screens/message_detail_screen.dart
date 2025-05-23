import 'dart:io';
import 'package:FANotifier/screens/user_profile_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'note_reply_screen.dart';
import '../utils.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'openjournal.dart';
import 'openpost.dart';

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
  final _secureStorage = const FlutterSecureStorage();
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
  String? messageId;
  String senderUsername = '';
  String senderLink = '';
  int pageNumber = 1;
  bool isClassic = false;

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
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message marked as unread')),
        );
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

  /// Custom link handling function to navigate within FA or externally
  Future<void> _handleFALink(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    final String urlToMatch = uri.toString();

    // 1. Gallery Folder Link
    final RegExp galleryFolderRegex = RegExp(
        r'^https?://(?:www\.)?furaffinity\.net/gallery/([^/]+)/folder/(\d+)/([^/]+)/?$'
    );
    if (galleryFolderRegex.hasMatch(urlToMatch)) {
      final match = galleryFolderRegex.firstMatch(urlToMatch)!;
      final String tappedUsername = match.group(1)!;
      final String folderNumber = match.group(2)!;
      final String folderName = match.group(3)!;
      final folderUrl =
          'https://www.furaffinity.net/gallery/$tappedUsername/folder/$folderNumber/$folderName/';

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            nickname: tappedUsername,
            initialSection: ProfileSection.Gallery,
            initialFolderUrl: folderUrl,
            initialFolderName: folderName,
          ),
        ),
      );
      return;
    }

    // 2. User Link
    final RegExp userRegex =
    RegExp(r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([^/]+)/?$');
    if (userRegex.hasMatch(urlToMatch)) {
      final String tappedUsername = userRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(nickname: tappedUsername),
        ),
      );
      return;
    }

    // 3. Journal Link
    final RegExp journalRegex =
    RegExp(r'^(?:https?://(?:www\.)?furaffinity\.net)?/journal/(\d+)/.*$');
    if (journalRegex.hasMatch(urlToMatch)) {
      final String journalId = journalRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenJournal(uniqueNumber: journalId),
        ),
      );
      return;
    }

    // 4. Submission/View Link
    final RegExp viewRegex = RegExp(
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$');
    if (viewRegex.hasMatch(urlToMatch)) {
      final String submissionId = viewRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenPost(
            uniqueNumber: submissionId,
            imageUrl: '',
          ),
        ),
      );
      return;
    }

    // 5. Fallback: external link
    await launchUrlString(url, mode: LaunchMode.externalApplication);
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
      child: WillPopScope(
        // Trigger refresh on back navigation
        onWillPop: () async {
          Navigator.pop(context, 'refresh');
          return false;
        },
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
                            _handleFALink(context, senderLink);
                          }
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          color: Colors.transparent,
                          child: CachedNetworkImage(
                            imageUrl: 'https:$avatarUrl',
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            errorWidget: (context, url, error) {
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sent by: $sender',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'To: $recipient',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Date: $sentDate',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(height: 20, thickness: 1, color: Colors.white54),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableLinkify(
                      key: _selectableKey,
                      onOpen: (link) async {
                        await _handleFALink(context, link.url);
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
                      ),
                      selectionControls: MaterialTextSelectionControls(),
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
                                username: senderUsername,
                                messageId: messageId ?? '',
                                messageLink: widget.messageLink,
                              ),
                            ),
                          ).then((result) {
                            if (result == 'marked_unread') {
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
    );
  }
}
