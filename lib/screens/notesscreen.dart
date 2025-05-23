import 'dart:async';
import 'dart:io';
import 'package:FANotifier/screens/user_profile_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher_string.dart';
import 'dart:convert';
import '../main.dart';
import '../utils/notes_notifications_text_edit.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'message_detail_screen.dart';
import 'message_model.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'new_message.dart';
import '../utils.dart';
import '../services/notification_service.dart';
import '../utils/message_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import '../../custom_drawer/drawer_user_controller.dart';
import 'openjournal.dart';
import 'openpost.dart';

/// NotesScreen uses edge-swipe logic to open a side drawer, similar to NotificationsScreen.
class NotesScreen extends StatefulWidget {
  final GlobalKey<DrawerUserControllerState> drawerKey;

  NotesScreen({
    Key? key,
    required this.drawerKey,
  }) : super(key: key);

  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with RouteAware {
  final _secureStorage = const FlutterSecureStorage();
  Timer? _refreshTimer;

  // For Inbox
  bool isLoadingInbox = true;
  bool isLoadingMoreInbox = false;
  String errorInbox = '';
  List<Message> inboxMessages = [];
  bool _isFetchingMoreInbox = false;
  int _currentInboxPage = 1;
  bool _hasMoreInbox = true;

  // For Sent
  bool isLoadingSent = true;
  bool isLoadingMoreSent = false;
  String errorSent = '';
  List<Message> sentMessages = [];
  bool _isFetchingMoreSent = false;
  int _currentSentPage = 1;
  bool _hasMoreSent = true;

  bool _isDialogOpen = false;

  final ScrollController _inboxScrollController = ScrollController();
  final ScrollController _sentScrollController = ScrollController();

  // Key to track if the "skip older unread" on first run is done
  static const _didFirstRunKey = 'did_first_run_skip';
  bool _didFirstRunSkip = false;

  // Variables for implementing an edge swipe to open the drawer
  bool _isDraggingFromEdge = false;
  double _startDragX = 0.0;

  @override
  void initState() {
    super.initState();
    // Checks if the skip had been done
    _checkFirstRunSkip().then((_) {
      // If not done => we do the "two-page fetch & skip" once
      if (!_didFirstRunSkip) {
        _fetchTwoPagesAndSkip().then((_) {
          // After that, load normal initial data
          _initInboxAndSent();
        });
      } else {
        // If already done => just do normal flows
        _initInboxAndSent();
      }
    });
  }

  Future<void> _checkFirstRunSkip() async {
    final prefs = await SharedPreferences.getInstance();
    _didFirstRunSkip = prefs.getBool(_didFirstRunKey) ?? false;
    print('[NotesScreen] _didFirstRunSkip? $_didFirstRunSkip');
  }

  Future<void> _setFirstRunSkipDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_didFirstRunKey, true);
    _didFirstRunSkip = true;
    print('[NotesScreen] setFirstRunSkipDone => true');
  }


  // On first run, fetch up to 2 pages of "inbox" => skip them
  Future<void> _fetchTwoPagesAndSkip() async {
    try {
      print('[NotesScreen] _fetchTwoPagesAndSkip => first run');
      final combined = <Message>[];

      // fetch 2 pages
      final page1 = await _fetchNotesPageWithoutUI('inbox', 1);
      combined.addAll(page1);

      final page2 = await _fetchNotesPageWithoutUI('inbox', 2);
      combined.addAll(page2);

      // gather unread
      final unread = combined.where((m) => m.isUnread).toList();
      if (unread.isNotEmpty) {
        final unreadIds = unread.map((e) => e.id).toList();
        await MessageStorage.addShownNoteIds(unreadIds);
        print(
          '[NotesScreen] first-run skip => added ${unreadIds.length} '
              'unread IDs to shown set',
        );
      }
      // Mark the skip done
      await _setFirstRunSkipDone();
    } catch (e) {
      print('[NotesScreen] _fetchTwoPagesAndSkip error => $e');
    }
  }

  // A helper that fetches page without messing with UI state
  Future<List<Message>> _fetchNotesPageWithoutUI(String folder, int page) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('No cookies => user not logged in?');
    }

    const int maxRetries = 10;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        // Show the "Trying again..." dialog if retrying
        if (retryCount > 0) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) => AlertDialog(
              content: Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      'Trying again... (Attempt ${retryCount + 1}/$maxRetries)',
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Performs the fetch
        final resp = await http.get(
          Uri.parse('https://www.furaffinity.net/msg/pms/$page/'),
          headers: {
            'Cookie': 'a=$cookieA; b=$cookieB; folder=$folder',
            'User-Agent': 'MyApp1.0',
          },
        );

        // Close the dialog if open
        if (retryCount > 0) Navigator.of(context).pop();

        // Check response status
        if (resp.statusCode == 200) {
          final decoded = utf8.decode(resp.bodyBytes, allowMalformed: true);
          final doc = html_parser.parse(decoded);
          final bool isClassic = doc.querySelector('body[data-static-path="/themes/classic"]') != null;

          var noteElements = doc.querySelectorAll('#notes-list .note-list-container');
          if (noteElements.isEmpty) {
            if (isClassic) {

              List<dom.Element> classicRows = List.from(doc.querySelectorAll('#notes-list tr.note'));
              // Check if the last element is not a note (e.g. it doesn't have an input checkbox).
              if (classicRows.isNotEmpty && classicRows.last.querySelector('input[type="checkbox"]') == null) {
                classicRows.removeLast();
              }
              noteElements = classicRows;
            }

          }


          final List<Message> fetched = [];
          for (var noteEl in noteElements) {
            final subject = noteEl.querySelector('.note-list-subject-container .c-noteListItem__subject')?.text.trim()
                ?? noteEl.querySelector('a.notelink.note-read.read')?.text.trim()
                ?? noteEl.querySelector('a.notelink.note-unread.unread')?.text.trim()
                ?? 'No subject';

            final sender = noteEl.querySelector('.c-usernameBlock__displayName .js-displayName')?.text.trim() ??
                noteEl.querySelector('div.c-usernameBlock.marquee-container a.c-usernameBlock__displayName.js-displayName-block span.js-displayName')?.text.trim() ??
                'Unknown sender';
            final date = noteEl.querySelector('.note-list-senddate span')?.attributes['title'] ??
                noteEl.querySelector('td.alt1.nowrap span.popup_date')?.attributes['title'] ??
                '';
            final link = noteEl.querySelector('.note-list-subject-container a')?.attributes['href'] ??
                noteEl.querySelector('a.notelink.note-unread.unread')?.attributes['href'] ??
                noteEl.querySelector('a.notelink.note-read.read')?.attributes['href'] ??
                '';

            final isUnread = folder == 'inbox' && (noteEl.querySelector('img.unread') != null ||
                noteEl.querySelector('img[src*="pms-unread.png"]') != null);

            final id = extractMessageId(link);

            fetched.add(Message(
              id: id,
              subject: subject,
              sender: sender,
              date: date,
              link: link,
              isUnread: isUnread,
            ));
          }
          return fetched;
        } else if (resp.statusCode == 503) {
          retryCount++;
          print('503 error, retrying in 3 seconds... Attempt: $retryCount');
          await Future.delayed(const Duration(seconds: 3));
        } else {
          throw Exception('HTTP error ${resp.statusCode} for page=$page');
        }
      } catch (e) {
        if (retryCount > 0) Navigator.of(context).pop();
        throw Exception('Error fetching page $page: $e');
      }
    }

    throw Exception('Max retries ($maxRetries) exceeded for page=$page');
  }

  // Normal initialization
  void _initInboxAndSent() {
    // Listen for scroll
    _inboxScrollController.addListener(() {
      if (_inboxScrollController.position.pixels ==
          _inboxScrollController.position.maxScrollExtent &&
          !_isFetchingMoreInbox &&
          _hasMoreInbox) {
        _loadMoreInbox();
      }
    });
    _sentScrollController.addListener(() {
      if (_sentScrollController.position.pixels ==
          _sentScrollController.position.maxScrollExtent &&
          !_isFetchingMoreSent &&
          _hasMoreSent) {
        _loadMoreSent();
      }
    });

    // Load first page
    _fetchInbox(page: 1);
    _fetchSent(page: 1);

    _startPeriodicFetch();
  }

  void _startPeriodicFetch() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 80), (_) {
      if (mounted && !_isDialogOpen) {
        print('Periodic fetch => ${DateTime.now()}');
        _fetchInboxTwoPagesOnly();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _refreshTimer?.cancel();
    _inboxScrollController.dispose();
    _sentScrollController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    if (!_isDialogOpen) {
      _fetchInboxTwoPagesOnly();
      _fetchSent(page: 1, clearOld: true);
    }
  }


  // 2-page fetch for quick new unread check
  Future<void> _fetchInboxTwoPagesOnly() async {
    try {
      List<Message> newFetched = [];
      newFetched.addAll(await _fetchNotesPageWithoutUI('inbox', 1));
      newFetched.addAll(await _fetchNotesPageWithoutUI('inbox', 2));

      await _handleNewUnreadMessages(newFetched);
    } catch (e) {
      print('[Foreground fetchInboxTwoPagesOnly] error => $e');
    }
  }


  // Normal pagination
  Future<void> _fetchInbox({int page = 1, bool clearOld = false}) async {
    print('[_fetchInbox] page=$page');
    if (page == 1) {
      setState(() {
        if (clearOld) inboxMessages.clear();
        isLoadingInbox = true;
        errorInbox = '';
        _hasMoreInbox = true;
      });
    }
    try {
      final newMessages = await _fetchNotesPageWithoutUI('inbox', page);
      if (page == 1) {
        setState(() {
          inboxMessages = newMessages;
        });
      } else {
        setState(() {
          inboxMessages.addAll(newMessages);
        });
      }

      setState(() {
        isLoadingInbox = false;
      });
      if (newMessages.isEmpty) {
        setState(() {
          _hasMoreInbox = false;
        });
      }

      // If the page is beyond the initial ones, marks unread messages as shown silently.
      if (page > 2) {
        final unread = newMessages.where((m) => m.isUnread).toList();
        if (unread.isNotEmpty) {
          final unreadIds = unread.map((m) => m.id).toList();
          await MessageStorage.addShownNoteIds(unreadIds);
          print('[handleNewUnreadMessages] Silently marked unread messages for page $page as shown: $unreadIds');
        }
      } else {
        // For pages 1 and 2, proceeds with normal notification handling.
        await _handleNewUnreadMessages(newMessages);
      }
    } catch (e) {
      setState(() {
        errorInbox = '$e';
        isLoadingInbox = false;
        _hasMoreInbox = false;
      });
    }
  }

  Future<void> _loadMoreInbox() async {
    _isFetchingMoreInbox = true;
    setState(() {
      isLoadingMoreInbox = true;
      _currentInboxPage++;
    });
    await _fetchInbox(page: _currentInboxPage);
    setState(() {
      isLoadingMoreInbox = false;
    });
    _isFetchingMoreInbox = false;
  }

  Future<void> _fetchSent({int page = 1, bool clearOld = false}) async {
    print('[_fetchSent] page=$page');
    if (page == 1) {
      setState(() {
        if (clearOld) sentMessages.clear();
        isLoadingSent = true;
        errorSent = '';
        _hasMoreSent = true;
      });
    }
    try {
      final newMessages = await _fetchNotesPageWithoutUI('sent', page);
      if (page == 1) {
        setState(() {
          if (clearOld) {
            sentMessages = newMessages;
          } else {
            sentMessages = newMessages;
          }
        });
      } else {
        setState(() {
          sentMessages.addAll(newMessages);
        });
      }

      setState(() {
        isLoadingSent = false;
      });
      if (newMessages.isEmpty) {
        setState(() {
          _hasMoreSent = false;
        });
      }
    } catch (e) {
      setState(() {
        errorSent = '$e';
        isLoadingSent = false;
        _hasMoreSent = false;
      });
    }
  }

  Future<void> _loadMoreSent() async {
    _isFetchingMoreSent = true;
    setState(() {
      isLoadingMoreSent = true;
      _currentSentPage++;
    });
    await _fetchSent(page: _currentSentPage);
    setState(() {
      isLoadingMoreSent = false;
    });
    _isFetchingMoreSent = false;
  }


  // Single note content
  Future<String> _fetchMessageContent(String link) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('No cookies => not logged in');
    }

    final dio = Dio();
    final cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));
    cookieJar.saveFromResponse(
      Uri.parse('https://www.furaffinity.net'),
      [Cookie('a', cookieA), Cookie('b', cookieB)],
    );

    final resp = await dio.get(
      'https://www.furaffinity.net$link',
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': 'FANotifier1.0',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        },
        validateStatus: (status) => status != null && status >= 200 && status < 400,
      ),
    );
    if (resp.statusCode == 200) {
      final doc = html_parser.parse(resp.data);

      // Check for modern layout
      final modernContentElement = doc.querySelector('.section-body .user-submitted-links');
      if (modernContentElement != null) {
        final rawHtml = modernContentElement.innerHtml;
        final innerDoc = html_parser.parse(rawHtml);

        // Replace truncated links
        innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
          final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
          if (fullLink != null) {
            anchor.innerHtml = fullLink;
          }
        });

        // Convert to plain text
        final updatedText = innerDoc.body?.text.trim() ?? '';
        // Return only the newest content
        final newestContent = extractNewestContent(updatedText);
        return newestContent.isNotEmpty ? newestContent : 'No content';
      } else {
        // Classic layout approach:
        final classicContentElement = doc.querySelector('td.noteContent.alt1');
        if (classicContentElement != null) {
          // Remove the header block (e.g. "Sent By:")
          classicContentElement.querySelector('span[style*="color: #999999"]')?.remove();

          final rawHtml = classicContentElement.innerHtml;
          final innerDoc = html_parser.parse(rawHtml);

          // Replace truncated links
          innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
            final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
            if (fullLink != null) {
              anchor.innerHtml = fullLink;
            }
          });

          // Convert to plain text
          final updatedText = innerDoc.body?.text.trim() ?? '';
          // Return only the newest content
          final newestContent = extractNewestContent(updatedText);
          return newestContent.isNotEmpty ? newestContent : 'No content';
        }
      }
      return 'No content';
    } else {
      throw Exception('Failed to fetch => ${resp.statusCode}');
    }
  }



  // handle new unread => notifications
  Future<void> _handleNewUnreadMessages(List<Message> fetchedInbox) async {
    try {
      final shownIds = await MessageStorage.getShownNoteIds();
      final unread = fetchedInbox.where((m) => m.isUnread).toList();
      if (unread.isEmpty) return;

      if (!_didFirstRunSkip) {
        // We have not done the skip => do not show anything
        print('[handleNewUnreadMessages] _didFirstRunSkip=false => ignoring');
        return;
      }

      // normal run
      final newUnread = unread.where((m) => !shownIds.contains(m.id)).toList();
      if (newUnread.isEmpty) return;

      for (var msg in newUnread) {
        try {
          final content = await _fetchMessageContent(msg.link);
          await NotificationService().showNotification(
            msg.id.hashCode,
            'New Note from ${msg.sender}',
            content,
            'note_${msg.id}',
            "notes",
          );

          // re-mark unread
          await _markAsUnreadWithoutRefetch(msg);
        } catch (e) {
          print('[handleNewUnreadMessages] err => $e');
        }
      }
      // add them to shown
      final newIds = newUnread.map((m) => m.id).toList();
      await MessageStorage.addShownNoteIds(newIds);
      print('[handleNewUnreadMessages] Notified => $newIds');
    } catch (e) {
      print('Error handleNewUnreadMessages => $e');
    }
  }

  Future<void> _markAsUnreadWithoutRefetch(Message msg) async {
    final String msgId = msg.id;
    if (msgId.isEmpty) {
      print('Invalid message ID');
      return;
    }

    // Determine page number: classic URLs always use page 1, and for modern URLs it extracts the page number from the URL.
    int pageNum;
    if (msg.link.contains('/viewmessage/')) {
      pageNum = 1;
    } else {
      final match = RegExp(r'/msg/pms/(\d+)/(\d+)/').firstMatch(msg.link);
      if (match != null) {
        pageNum = int.parse(match.group(1)!);
      } else {
        pageNum = 1;
      }
    }
    print("Marking message as unread using id: $msgId on page: $pageNum");

    try {
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) {
        throw Exception('No cookies => markAsUnreadWithoutRefetch fail');
      }

      final dio = Dio();
      final cookieJar = CookieJar();
      dio.interceptors.add(CookieManager(cookieJar));
      cookieJar.saveFromResponse(
        Uri.parse('https://www.furaffinity.net'),
        [Cookie('a', cookieA), Cookie('b', cookieB)],
      );


      final Map<String, dynamic> formData = {
        'manage_notes': '1',
        'items[]': msgId,
        'move_to': 'unread',
      };


      final response = await dio.post(
        'https://www.furaffinity.net/msg/pms/$pageNum/$msgId/',
        data: formData,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://www.furaffinity.net/msg/pms/$pageNum/$msgId/',
            'Origin': 'https://www.furaffinity.net',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
            'Cache-Control': 'max-age=0',
            'DNT': '1',
            'Upgrade-Insecure-Requests': '1',
          },
          followRedirects: false,
          validateStatus: (s) => s != null && ((s >= 200 && s < 400) || s == 302),
        ),
      );

      if (response.statusCode == 302 || response.statusCode == 200) {
        print('[_markAsUnreadWithoutRefetch] success for $msgId');
      } else {
        throw Exception('Failed to mark as unread: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in _markAsUnreadWithoutRefetch: $e');
    }
  }



  // UI BUILD
  Widget _buildMessageList({
    required bool isLoading,
    required bool isLoadingMore,
    required String errorMessage,
    required List<Message> messages,
    required String folder,
    required ScrollController scrollController,
    required bool hasMore,
    required Function loadMore,
  }) {
    if (isLoading && messages.isEmpty) {
      return const Center(child: PulsatingLoadingIndicator(size: 108.0, assetPath: 'assets/icons/fathemed.png'));
    } else if (errorMessage.isNotEmpty && messages.isEmpty) {
      return Center(
        child: Text(
          errorMessage,
          style: const TextStyle(color: Colors.red, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    } else if (messages.isEmpty) {
      return const Center(
        child: Text(
          'No messages found.',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    } else {
      return RefreshIndicator(
        onRefresh: () async {
          if (folder == 'inbox') {
            _currentInboxPage = 1;
            _hasMoreInbox = true;
            await _fetchInbox(page: 1, clearOld: true);
          } else {
            _currentSentPage = 1;
            _hasMoreSent = true;
            await _fetchSent(page: 1, clearOld: true);
          }
        },
        child: ListView.builder(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: messages.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == messages.length) {
              // Shows loading indicator at the end with extra padding
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 44.0),
                child: Center(
                  child: isLoadingMore
                      ? const CircularProgressIndicator()
                      : const SizedBox.shrink(),
                ),
              );
            }

            final msg = messages[index];
            return GestureDetector(
              onTap: () {
                // Now captures the pop result when returning from MessageDetailScreen
                Navigator.of(context)
                    .push(MaterialPageRoute(
                  builder: (_) => MessageDetailScreen(
                    messageLink: msg.link,
                    folder: folder,
                  ),
                ))
                    .then((result) {
                  if (result == 'refresh' || result == 'marked_unread') {
                    _fetchInbox(page: 1, clearOld: true);
                    _fetchSent(page: 1, clearOld: true);
                  }
                });
              },
              child: Column(
                children: [
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 16.0,
                    ),
                    child: Row(
                      children: [
                        if (msg.isUnread && folder == 'inbox')
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 16),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFE09321),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.subject,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'From: ${msg.sender}\nDate: ${msg.date}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.preview, color: Colors.white),
                          tooltip: 'Preview',
                          onPressed: () => _showPreviewDialog(msg, folder),
                        ),
                      ],
                    ),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 0.2,
                    color: Colors.grey,
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
  }

  void _showPreviewDialog(Message message, String folder) {
    bool wasInitiallyUnread = message.isUnread;

    setState(() {
      _isDialogOpen = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          insetPadding:
          const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          backgroundColor: Colors.grey[900],
          child: PreviewDialogContent(
            message: message,
            folder: folder,
            onMarkedUnread: wasInitiallyUnread && folder != 'sent'
                ? () => _markAsUnreadWithoutRefetch(message)
                : null,
          ),
        );
      },
    ).then((_) {
      setState(() {
        _isDialogOpen = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = isLoadingInbox || isLoadingSent;

    // Shows a loading indicator if both inbox and sent messages are loading
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notes'),
          centerTitle: true,
          backgroundColor: Colors.black,
        ),
        backgroundColor: Colors.black,
        body: const Center(child: PulsatingLoadingIndicator(size: 88.0, assetPath: 'assets/icons/fathemed.png'))
      );
    }

    return DefaultTabController(
      length: 2, // Number of tabs
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('Notes'),
              centerTitle: true,
              backgroundColor: Colors.black,
              bottom: const TabBar(
                indicator: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(width: 2.5, color: Color(0xFFE09321)),
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: TextStyle(
                  fontSize: 19.0,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: TextStyle(fontSize: 17.0),
                tabs: [
                  Tab(text: 'Inbox'),
                  Tab(text: 'Sent'),
                ],
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.0),
              child: Builder(
                builder: (innerContext) => NotificationListener<OverscrollNotification>(
                  onNotification: (OverscrollNotification notification) {
                    final tabIndex = DefaultTabController.of(innerContext)?.index ?? 0;
                    if (tabIndex == 0 &&
                        notification.metrics.axis == Axis.horizontal &&
                        notification.overscroll < 0) {
                      widget.drawerKey.currentState?.openDrawer();
                      return true;
                    }

                    return false;
                  },
                  child: TabBarView(
                    children: [
                      _buildMessageList(
                        isLoading: isLoadingInbox,
                        isLoadingMore: isLoadingMoreInbox,
                        errorMessage: errorInbox,
                        messages: inboxMessages,
                        folder: 'inbox',
                        scrollController: _inboxScrollController,
                        hasMore: _hasMoreInbox,
                        loadMore: _loadMoreInbox,
                      ),
                      _buildMessageList(
                        isLoading: isLoadingSent,
                        isLoadingMore: isLoadingMoreSent,
                        errorMessage: errorSent,
                        messages: sentMessages,
                        folder: 'sent',
                        scrollController: _sentScrollController,
                        hasMore: _hasMoreSent,
                        loadMore: _loadMoreSent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            floatingActionButton: FloatingActionButton(
              backgroundColor: Color(0xFFE09321),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => NewMessageScreen()),
                );
              },
              shape: const CircleBorder(),
              child: const Icon(Icons.message),
            ),
            backgroundColor: Colors.black,
          ),

          // Positioned GestureDetector for manual dragging from left edge
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 25,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (DragStartDetails details) {
                const edgeWidth = 62.0;
                if (details.globalPosition.dx <= edgeWidth) {
                  _isDraggingFromEdge = true;
                  _startDragX = details.globalPosition.dx;
                }
              },
              onHorizontalDragUpdate: (DragUpdateDetails details) {
                if (_isDraggingFromEdge) {
                  final drawerState = widget.drawerKey.currentState;
                  if (drawerState != null) {
                    final drawerWidth = drawerState.widget.drawerWidth;
                    final currentOffset =
                        drawerState.scrollController?.offset ?? drawerWidth;

                    double newOffset = currentOffset - details.delta.dx;
                    if (newOffset < 0) newOffset = 0;
                    if (newOffset > drawerWidth) newOffset = drawerWidth;

                    drawerState.setDrawerPosition(newOffset);
                  }
                }
              },
              onHorizontalDragEnd: (DragEndDetails details) {
                if (_isDraggingFromEdge) {
                  _isDraggingFromEdge = false;
                  final drawerState = widget.drawerKey.currentState;
                  if (drawerState != null) {
                    final drawerWidth = drawerState.widget.drawerWidth;
                    final currentOffset =
                        drawerState.scrollController?.offset ?? drawerWidth;
                    final threshold = drawerWidth / 2;

                    if (currentOffset < threshold) {
                      drawerState.openDrawer();
                    } else {
                      drawerState.closeDrawer();
                    }
                  }
                }
              },
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }

}

// PREVIEW DIALOG
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
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
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
    _dio.options.headers['User-Agent'] =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/130.0.0.0 Safari/537.36';
    _dio.options.followRedirects = true;
    _dio.options.validateStatus =
        (status) => status != null && status >= 200 && status < 400;
  }

  Future<void> _loadCookies() async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    final cookies = <Cookie>[];
    if (cookieA != null) cookies.add(Cookie('a', cookieA));
    if (cookieB != null) cookies.add(Cookie('b', cookieB));

    cookies.add(Cookie('folder', widget.folder));

    final uri = Uri.parse('https://www.furaffinity.net');
    _cookieJar.saveFromResponse(uri, cookies);
  }

  Future<void> _fetchMessageDetails() async {
    try {
      await _loadCookies();
      print("preview debug link: ${widget.message.link}");
      final response = await _dio.get(
        'https://www.furaffinity.net${widget.message.link}',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          },
        ),
      );

      if (response.statusCode == 200) {
        final decodedBody = response.data;
        final document = html_parser.parse(decodedBody);


        _isClassic = document.querySelector(
          'body[data-static-path="/themes/classic"][id="pageid-messagecenter-pms-view"]',
        ) != null;
        print("Layout detected: ${_isClassic ? 'Classic' : 'Modern'}");



        String extractedId;
        if (_isClassic) {
          final match = RegExp(r'/viewmessage/(\d+)/').firstMatch(widget.message.link);
          print("Classic URL match: $match");
          if (match != null) {
            extractedId = match.group(1)!;
            pageNumber = 1;
          } else {
            throw Exception("Message ID could not be extracted from classic URL.");
          }
        } else {
          final match = RegExp(r'/msg/pms/(\d+)/(\d+)/').firstMatch(widget.message.link);
          print("Modern URL match: $match");
          if (match != null) {
            pageNumber = int.parse(match.group(1)!);
            extractedId = match.group(2)!;
          } else {
            throw Exception("Message ID could not be extracted from modern URL.");
          }
        }
        print("Extracted messageId: $extractedId, pageNumber: $pageNumber");


        // Removes scam/warning blocks.
        document.querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
            .forEach((e) => e.remove());

        // Extracting sender link and username.
        final tempSenderLink = document
            .querySelector('.message-center-note-information .addresses a')
            ?.attributes['href'] ??
            document
                .querySelector('div.message-center-note-information.addresses a')
                ?.attributes['href'];
        if (tempSenderLink != null && tempSenderLink.isNotEmpty) {
          senderLink = tempSenderLink;
          senderUsername = Uri.parse(tempSenderLink).pathSegments.length >= 2
              ? Uri.parse(tempSenderLink).pathSegments[1]
              : 'Unknown';
        } else {
          senderUsername = 'Unknown';
        }
        print("Sender: $senderUsername, senderLink: $senderLink");


        setState(() {
          subject = document.querySelector('#message h2')?.text.trim() ??
              document.querySelector('td.cat font b')?.text.trim() ??
              'No subject';

          sender = document.querySelector('.message-center-note-information .addresses a')
              ?.text
              .trim() ??
              document
                  .querySelector('a.c-usernameBlock__displayName.js-displayName-block span.js-displayName')
                  ?.text
                  .trim() ??
              'Unknown sender';

          if (_isClassic) {
            final classicRecipientBlocks = document.querySelectorAll(
                'span[style*="color: #999999"] .c-usernameBlock');
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
            final recipientBlocks = document.querySelectorAll(
                '.message-center-note-information .addresses .c-usernameBlock');
            recipient = (recipientBlocks.length > 1
                ? recipientBlocks[1]
                .querySelector('.c-usernameBlock__displayName')
                ?.text
                .trim()
                : null) ??
                'Unknown recipient';
          }

          sentDate = document.querySelector('.popup_date')?.attributes['title'] ?? 'Unknown date';
          avatarUrl = document.querySelector('.message-center-note-information.avatar img')
              ?.attributes['src'] ??
              '';

          // Untruncates the note content.
          final modernElem = document.querySelector('.section-body .user-submitted-links');
          final classicContentElement = document.querySelector('td.noteContent.alt1');
          String? modernHtml;
          String? classicHtml;
          if (modernElem != null) {
            modernHtml = modernElem.innerHtml;
          }
          if (classicContentElement != null) {
            // Removes the header block
            classicContentElement.querySelector('span[style*="color: #999999"]')?.remove();
            classicHtml = classicContentElement.innerHtml;
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

        print("Fetched details: subject: $subject, sender: $sender, recipient: $recipient, "
            "sentDate: $sentDate, avatarUrl: $avatarUrl, content (first 50 chars): "
            "${messageContent.substring(0, messageContent.length > 50 ? 50 : messageContent.length)}");

        if (widget.onMarkedUnread != null) {
          print("onMarkedUnread callback is provided. Invoking callback now...");
          widget.onMarkedUnread!();
        } else {
          print("No onMarkedUnread callback provided.");
        }
      } else {
        setState(() {
          errorMessage = 'Failed to fetch message: ${response.statusCode}';
          isLoading = false;
        });
        print("Response status code: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
        isLoading = false;
      });
      print("Error in _fetchMessageDetails: $e");
    }
  }




  Future<void> _handleFALink(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    final String urlToMatch = uri.toString();

    // 1) Gallery Folder
    final RegExp galleryFolderRegex = RegExp(
      r'^https?://(?:www\.)?furaffinity\.net/gallery/([^/]+)/folder/(\d+)/([^/]+)/?$',
    );
    if (galleryFolderRegex.hasMatch(urlToMatch)) {
      final match = galleryFolderRegex.firstMatch(urlToMatch)!;
      final tappedUsername = match.group(1)!;
      final folderNumber = match.group(2)!;
      final folderName = match.group(3)!;
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

    // 2) User link
    final RegExp userRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([^/]+)/?$',
    );
    if (userRegex.hasMatch(urlToMatch)) {
      final tappedUsername = userRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(nickname: tappedUsername),
        ),
      );
      return;
    }

    // 3) Journal
    final RegExp journalRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/journal/(\d+)/.*$',
    );
    if (journalRegex.hasMatch(urlToMatch)) {
      final journalId = journalRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenJournal(uniqueNumber: journalId),
        ),
      );
      return;
    }

    // 4) Submission
    final RegExp viewRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$',
    );
    if (viewRegex.hasMatch(urlToMatch)) {
      final submissionId = viewRegex.firstMatch(urlToMatch)!.group(1)!;
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

    // 5) Fallback external link
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: isLoading
          ? const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(child: CircularProgressIndicator()),
      )
          : errorMessage.isNotEmpty
          ? Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // hide avatar if page is Classic
                if (!_isClassic)
          GestureDetector(
          onTap: () {
    if (senderLink.isNotEmpty) {
    _handleFALink(context, senderLink);
    }
    },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          borderRadius: BorderRadius.zero,
        ),
        child: avatarUrl.isNotEmpty
            ? CachedNetworkImage(
          imageUrl: 'https:$avatarUrl',
          fit: BoxFit.cover,
          errorWidget: (ctx, url, error) => Image.asset(
            'assets/images/defaultpic.gif',
            fit: BoxFit.cover,
          ),
        )
            : Image.asset(
          'assets/images/defaultpic.gif',
          fit: BoxFit.cover,
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
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(
              height: 20,
              thickness: 1,
              color: Colors.white54,
            ),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableLinkify(
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
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFE09321),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
