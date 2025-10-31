import 'dart:async';
import 'dart:io';
import 'package:FANotifier/screens/user_profile_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher_string.dart';
import 'dart:convert';
import '../main.dart';
import 'package:FANotifier/services/notes_refresh_service.dart';
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

class NotesScreen extends StatefulWidget {
  final GlobalKey<DrawerUserControllerState> drawerKey;
  final bool forceRefresh;

  NotesScreen({
    Key? key,
    required this.drawerKey,
    this.forceRefresh = false,
  }) : super(key: key);

  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen>
    with RouteAware, WidgetsBindingObserver {
  final _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
        accountName: 'flutter_secure_storage_service',
        accessibility: KeychainAccessibility.first_unlock),
  );
  Timer? _refreshTimer;
  StreamSubscription<void>? _notesRefreshSub;

  bool isLoadingInbox = true;
  bool isLoadingMoreInbox = false;
  String errorInbox = '';
  List<Message> inboxMessages = [];
  bool _isFetchingMoreInbox = false;
  int _currentInboxPage = 1;
  bool _hasMoreInbox = true;

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

  static const _didFirstRunKey = 'did_first_run_skip';
  bool _didFirstRunSkip = false;

  bool _isDraggingFromEdge = false;
  double _startDragX = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.forceRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchInbox(page: 1, clearOld: true);
        _fetchSent(page: 1, clearOld: true);
      });
    }

    _checkFirstRunSkip().then((_) {
      if (!_didFirstRunSkip) {
        _fetchTwoPagesAndSkip().then((_) {
          _initInboxAndSent();
        });
      } else {
        _initInboxAndSent();
      }
    });

    _notesRefreshSub = NotesRefreshService().stream.listen((_) {
      if (!mounted) return;
      _fetchInbox(page: 1, clearOld: true);
      _fetchSent(page: 1, clearOld: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _refreshTimer?.cancel();
    _inboxScrollController.dispose();
    _sentScrollController.dispose();
    _notesRefreshSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    if (!_isDialogOpen) {
      _fetchInboxTwoPagesOnly();
      _fetchSent(page: 1, clearOld: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_isDialogOpen) {
      errorInbox = '';
      errorSent = '';
      _currentInboxPage = 1;
      _currentSentPage = 1;
      _hasMoreInbox = true;
      _hasMoreSent = true;
      _fetchInbox(page: 1, clearOld: true);
      _fetchSent(page: 1, clearOld: true);
      _startPeriodicFetch();
    }
  }

  Future<void> _checkFirstRunSkip() async {
    final prefs = await SharedPreferences.getInstance();
    _didFirstRunSkip = prefs.getBool(_didFirstRunKey) ?? false;
  }

  Future<void> _setFirstRunSkipDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_didFirstRunKey, true);
    _didFirstRunSkip = true;
  }

  Future<void> _fetchTwoPagesAndSkip() async {
    try {
      final combined = <Message>[];
      final page1 = await _fetchNotesPageWithoutUI('inbox', 1);
      combined.addAll(page1);
      final page2 = await _fetchNotesPageWithoutUI('inbox', 2);
      combined.addAll(page2);

      final unread = combined.where((m) => m.isUnread).toList();
      if (unread.isNotEmpty) {
        final unreadIds = unread.map((e) => e.id).toList();
        await MessageStorage.addShownNoteIds(unreadIds);
      }
      await _setFirstRunSkipDone();
    } catch (_) {}
  }

  void _initInboxAndSent() {
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

    _fetchInbox(page: 1);
    _fetchSent(page: 1);
    _startPeriodicFetch();
  }

  void _startPeriodicFetch() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 80), (_) {
      if (mounted && !_isDialogOpen) {
        _fetchInboxTwoPagesOnly();
      }
    });
  }

  Future<void> _fetchInboxTwoPagesOnly() async {
    try {
      List<Message> newFetched = [];
      newFetched.addAll(await _fetchNotesPageWithoutUI('inbox', 1));
      newFetched.addAll(await _fetchNotesPageWithoutUI('inbox', 2));
      await _handleNewUnreadMessages(newFetched);
    } catch (e) {
      debugPrint('[Foreground fetchInboxTwoPagesOnly] error => $e');
    }
  }

  Future<void> _fetchInbox({int page = 1, bool clearOld = false}) async {
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

      if (page > 2) {
        final unread = newMessages.where((m) => m.isUnread).toList();
        if (unread.isNotEmpty) {
          final unreadIds = unread.map((m) => m.id).toList();
          await MessageStorage.addShownNoteIds(unreadIds);
        }
      } else {
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
          sentMessages = newMessages;
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

  Future<http.Response> _faGet({
    required String url,
    required String cookieA,
    required String cookieB,
    required String folder,
  }) async {
    final ioHttp = HttpClient()
      ..idleTimeout = Duration.zero
      ..connectionTimeout = const Duration(seconds: 20);
    final client = IOClient(ioHttp);
    try {
    final resp = await client
        .get(
    Uri.parse(url),
    headers: {
    'Cookie': 'a=$cookieA; b=$cookieB; folder=$folder',
    'User-Agent': 'FANotifier1.0',
    HttpHeaders.connectionHeader: 'close',
    'Accept':
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    },
    )
        .timeout(const Duration(seconds: 30));
    return resp;
    } finally {
    client.close();
    ioHttp.close(force: true);
    }
  }

  Future<List<Message>> _fetchNotesPageWithoutUI(String folder, int page) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('No cookies => user not logged in?');
    }

    const int maxRetries = 4;
    int retry = 0;
    Duration backoff = const Duration(seconds: 2);

    while (true) {
      try {
        final resp = await _faGet(
          url: 'https://www.furaffinity.net/msg/pms/$page/',
          cookieA: cookieA,
          cookieB: cookieB,
          folder: folder,
        );

        if (resp.statusCode == 200) {
          final decoded = utf8.decode(resp.bodyBytes, allowMalformed: true);
          final doc = html_parser.parse(decoded);
          final bool isClassic =
              doc.querySelector('body[data-static-path="/themes/classic"]') !=
                  null;

          var noteElements =
          doc.querySelectorAll('#notes-list .note-list-container');
          if (noteElements.isEmpty) {
            if (isClassic) {
              List<dom.Element> classicRows =
              List.from(doc.querySelectorAll('#notes-list tr.note'));
              if (classicRows.isNotEmpty &&
                  classicRows.last
                      .querySelector('input[type="checkbox"]') ==
                      null) {
                classicRows.removeLast();
              }
              noteElements = classicRows;
            }
          }

          final List<Message> fetched = [];
          for (var noteEl in noteElements) {
            final subject = noteEl
                .querySelector(
                '.note-list-subject-container .c-noteListItem__subject')
                ?.text
                .trim() ??
                noteEl
                    .querySelector('a.notelink.note-read.read')
                    ?.text
                    .trim() ??
                noteEl
                    .querySelector('a.notelink.note-unread.unread')
                    ?.text
                    .trim() ??
                'No subject';

            final sender = noteEl
                .querySelector(
                '.c-usernameBlock__displayName .js-displayName')
                ?.text
                .trim() ??
                noteEl
                    .querySelector(
                    'div.c-usernameBlock.marquee-container a.c-usernameBlock__displayName.js-displayName-block span.js-displayName')
                    ?.text
                    .trim() ??
                'Unknown sender';

            final date = noteEl
                .querySelector('.note-list-senddate span')
                ?.attributes['title'] ??
                noteEl
                    .querySelector('td.alt1.nowrap span.popup_date')
                    ?.attributes['title'] ??
                '';

            final link = noteEl
                .querySelector('.note-list-subject-container a')
                ?.attributes['href'] ??
                noteEl
                    .querySelector('a.notelink.note-unread.unread')
                    ?.attributes['href'] ??
                noteEl
                    .querySelector('a.notelink.note-read.read')
                    ?.attributes['href'] ??
                '';

            final isUnread = (noteEl.querySelector('img.unread') != null ||
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
          retry++;
          if (retry > maxRetries) {
            throw Exception('HTTP 503 after $maxRetries retries');
          }
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        } else {
          throw Exception('HTTP error ${resp.statusCode} for page=$page');
        }
      } on TimeoutException catch (e) {
        retry++;
        if (retry > maxRetries) {
          throw Exception('Timeout after $maxRetries retries: $e');
        }
        await Future.delayed(backoff);
        backoff *= 2;
        continue;
      } on SocketException catch (e) {
        retry++;
        if (retry > maxRetries) {
          throw Exception('SocketException after $maxRetries retries: $e');
        }
        await Future.delayed(backoff);
        backoff *= 2;
        continue;
      } catch (e) {
        throw Exception('Error fetching page $page: $e');
      }
    }
  }

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
          'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          HttpHeaders.connectionHeader: 'close',
        },
        validateStatus: (status) =>
        status != null && status >= 200 && status < 400,
      ),
    );
    if (resp.statusCode == 200) {
      final doc = html_parser.parse(resp.data);

      final modernContentElement =
      doc.querySelector('.section-body .user-submitted-links');
      if (modernContentElement != null) {
        modernContentElement
            .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
            .forEach((e) => e.remove());

        final rawHtml = modernContentElement.innerHtml;
        final innerDoc = html_parser.parse(rawHtml);

        innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
          final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
          if (fullLink != null) {
            anchor.innerHtml = fullLink;
          }
        });

        final updatedText = innerDoc.body?.text.trim() ?? '';
        final newestContent = extractNewestContent(updatedText);
        return newestContent.isNotEmpty ? newestContent : 'No content';
      } else {
        final classicContentElement = doc.querySelector('td.noteContent.alt1');
        if (classicContentElement != null) {
          classicContentElement
              .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
              .forEach((e) => e.remove());
          classicContentElement
              .querySelector('span[style*="color: #999999"]')
              ?.remove();

          final rawHtml = classicContentElement.innerHtml;
          final innerDoc = html_parser.parse(rawHtml);

          innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
            final fullLink = anchor.attributes['title'] ?? anchor.attributes['href'];
            if (fullLink != null) {
              anchor.innerHtml = fullLink;
            }
          });

          final updatedText = innerDoc.body?.text.trim() ?? '';
          final newestContent = extractNewestContent(updatedText);
          return newestContent.isNotEmpty ? newestContent : 'No content';
        }
      }
      return 'No content';
    } else {
      throw Exception('Failed to fetch => ${resp.statusCode}');
    }
  }

  Future<void> _handleNewUnreadMessages(List<Message> fetchedInbox) async {
    try {
      final shownIds = await MessageStorage.getShownNoteIds();
      final unread = fetchedInbox.where((m) => m.isUnread).toList();
      if (unread.isEmpty) return;

      if (!_didFirstRunSkip) {
        return;
      }

      final newUnread =
      unread.where((m) => !shownIds.contains(m.id)).toList();
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

          await _markAsUnreadWithoutRefetch(msg);
        } catch (_) {}
      }
      final newIds = newUnread.map((m) => m.id).toList();
      await MessageStorage.addShownNoteIds(newIds);
    } catch (_) {}
  }

  Future<void> _markAsUnreadWithoutRefetch(Message msg) async {
    final String msgId = msg.id;
    if (msgId.isEmpty) return;

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

    try {
      final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
      final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
      if (cookieA == null || cookieB == null) return;

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
            'Referer':
            'https://www.furaffinity.net/msg/pms/$pageNum/$msgId/',
            'Origin': 'https://www.furaffinity.net',
            'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
            HttpHeaders.connectionHeader: 'close',
            'Cache-Control': 'max-age=0',
            'DNT': '1',
            'Upgrade-Insecure-Requests': '1',
          },
          followRedirects: false,
          validateStatus: (s) =>
          s != null && ((s >= 200 && s < 400) || s == 302),
        ),
      );

      if (response.statusCode != 302 && response.statusCode != 200) {
        throw Exception('Failed to mark as unread: ${response.statusCode}');
      }
    } catch (_) {}
  }

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
      return const Center(
          child: PulsatingLoadingIndicator(
              size: 108.0, assetPath: 'assets/icons/fathemed.png'));
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
                        if (msg.isUnread)
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
                        if (folder == 'inbox')
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

    if (isLoading) {
      return Scaffold(
          appBar: AppBar(
            title: const Text('Notes'),
            centerTitle: true,
            backgroundColor: Colors.black,
          ),
          backgroundColor: Colors.black,
          body: const Center(
              child: PulsatingLoadingIndicator(
                  size: 88.0, assetPath: 'assets/icons/fathemed.png')));
    }

    return DefaultTabController(
      length: 2,
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
                builder: (innerContext) =>
                    NotificationListener<OverscrollNotification>(
                      onNotification: (OverscrollNotification notification) {
                        final tabIndex =
                            DefaultTabController.of(innerContext)?.index ?? 0;
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
              backgroundColor: const Color(0xFFE09321),
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
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
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

        String extractedId;
        if (_isClassic) {
          final match =
          RegExp(r'/viewmessage/(\d+)/').firstMatch(widget.message.link);
          if (match != null) {
            extractedId = match.group(1)!;
            pageNumber = 1;
          } else {
            throw Exception(
                "Message ID could not be extracted from classic URL.");
          }
        } else {
          final match =
          RegExp(r'/msg/pms/(\d+)/(\d+)/').firstMatch(widget.message.link);
          if (match != null) {
            pageNumber = int.parse(match.group(1)!);
            extractedId = match.group(2)!;
          } else {
            throw Exception(
                "Message ID could not be extracted from modern URL.");
          }
        }

        final tempSenderLink = document
            .querySelector('.message-center-note-information .addresses a')
            ?.attributes['href'] ??
            document
                .querySelector(
                'div.message-center-note-information.addresses a')
                ?.attributes['href'];
        if (tempSenderLink != null && tempSenderLink.isNotEmpty) {
          senderLink = tempSenderLink;
          senderUsername = Uri.parse(tempSenderLink).pathSegments.length >= 2
              ? Uri.parse(tempSenderLink).pathSegments[1]
              : 'Unknown';
        } else {
          senderUsername = 'Unknown';
        }

        setState(() {
          subject = document.querySelector('#message h2')?.text.trim() ??
              document.querySelector('td.cat font b')?.text.trim() ??
              'No subject';

          sender = document
              .querySelector(
              '.message-center-note-information .addresses a')
              ?.text
              .trim() ??
              document
                  .querySelector(
                  'a.c-usernameBlock__displayName.js-displayName-block span.js-displayName')
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

          sentDate = document
              .querySelector('.popup_date')
              ?.attributes['title'] ??
              'Unknown date';
          avatarUrl = document
              .querySelector(
              '.message-center-note-information.avatar img')
              ?.attributes['src'] ??
              '';

          final modernElem =
          document.querySelector('.section-body .user-submitted-links');
          final classicContentElement =
          document.querySelector('td.noteContent.alt1');
          String? modernHtml;
          String? classicHtml;
          if (modernElem != null) {
            modernElem
                .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
                .forEach((e) => e.remove());
            modernHtml = modernElem.innerHtml;
          }
          if (classicContentElement != null) {
            classicContentElement
                .querySelectorAll('.noteWarningMessage.noteWarningMessage--scam')
                .forEach((e) => e.remove());
            classicContentElement
                .querySelector('span[style*="color: #999999"]')
                ?.remove();
            classicHtml = classicContentElement.innerHtml;
          }
          final rawHtml = modernHtml ?? classicHtml;
          if (rawHtml == null || rawHtml.isEmpty) {
            messageContent = 'No content';
          } else {
            final innerDoc = html_parser.parse(rawHtml);
            innerDoc.querySelectorAll('a.auto_link_shortened').forEach((anchor) {
              final fullLink =
                  anchor.attributes['title'] ?? anchor.attributes['href'];
              if (fullLink != null) {
                anchor.innerHtml = fullLink;
              }
            });
            final updatedText = innerDoc.body?.text.trim() ?? '';
            messageContent =
            updatedText.isNotEmpty ? updatedText : 'No content';
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

  Future<void> _handleFALink(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    final String urlToMatch = uri.toString();

    final RegExp galleryFolderRegex = RegExp(
      r'^https?://(?:www\.)?furaffinity\.net/gallery/([a-zA-Z0-9\-_.~]+)/folder/(\d+)/([a-zA-Z0-9\-_.~]+)/?$',
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

    final RegExp userRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([a-zA-Z0-9\-_.~]+)/?$',
    );
    if (userRegex.hasMatch(urlToMatch)) {
      final String tappedUsername =
      userRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(nickname: tappedUsername),
        ),
      );
      return;
    }

    final RegExp journalRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/(?:journals/([a-zA-Z0-9\-_.~]+)|journal/(\d+))(?:/.*)?(?:#.*)?$',
    );

    if (journalRegex.hasMatch(urlToMatch)) {
      final Match match = journalRegex.firstMatch(urlToMatch)!;
      final String? username = match.group(1);
      final String? journalId = match.group(2);

      if (username != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(
              nickname: username,
              initialSection: ProfileSection.Journals,
            ),
          ),
        );
      } else if (journalId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OpenJournal(uniqueNumber: journalId),
          ),
        );
      }

      return;
    }

    final RegExp viewRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$',
    );
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
            style:
            const TextStyle(color: Colors.red, fontSize: 16),
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
                        errorWidget: (ctx, url, error) =>
                            Image.asset(
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
                    backgroundColor: const Color(0xFFE09321),
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
