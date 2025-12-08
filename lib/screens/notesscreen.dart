import 'dart:async';
import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../main.dart';
import 'package:FANotifier/services/notes_refresh_service.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'message_detail_screen.dart';
import 'message_model.dart';
import 'new_message.dart';
import '../services/notification_service.dart';
import '../utils/message_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../custom_drawer/drawer_user_controller.dart';
import 'notesscreen_api_service.dart';
import 'notesscreen_preview_dialog.dart';
import 'notesscreen_widgets.dart';
import 'notesscreen_inbox.dart';
import 'notesscreen_sent.dart';

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
  late final NotesApiService _notesApi;
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
    _notesApi = NotesApiService(_secureStorage);

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
      final page1 = await _notesApi.fetchNotesPage(folder: 'inbox', page: 1);
      combined.addAll(page1);
      final page2 = await _notesApi.fetchNotesPage(folder: 'inbox', page: 2);
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
      newFetched.addAll(await _notesApi.fetchNotesPage(folder: 'inbox', page: 1));
      newFetched.addAll(await _notesApi.fetchNotesPage(folder: 'inbox', page: 2));
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
      final newMessages = await _notesApi.fetchNotesPage(folder: 'inbox', page: page);
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
      final newMessages = await _notesApi.fetchNotesPage(folder: 'sent', page: page);
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
          final content = await _notesApi.fetchMessageContent(msg.link);
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

  // Message list UI moved to notesscreen_widgets.dart (MessageList)

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
                          InboxTab(
                            isLoading: isLoadingInbox,
                            isLoadingMore: isLoadingMoreInbox,
                            errorMessage: errorInbox,
                            messages: inboxMessages,
                            scrollController: _inboxScrollController,
                            hasMore: _hasMoreInbox,
                            refreshInbox: () async {
                              _currentInboxPage = 1;
                              _hasMoreInbox = true;
                              await _fetchInbox(page: 1, clearOld: true);
                            },
                            refreshSent: () async {
                              _currentSentPage = 1;
                              _hasMoreSent = true;
                              await _fetchSent(page: 1, clearOld: true);
                            },
                            loadMore: _loadMoreInbox,
                            onOpenMessage: (msg) {
                              Navigator.of(context)
                                  .push(MaterialPageRoute(
                                builder: (_) => MessageDetailScreen(
                                  messageLink: msg.link,
                                  folder: 'inbox',
                                ),
                              ))
                                  .then((result) {
                                if (result == 'refresh' || result == 'marked_unread') {
                                  _fetchInbox(page: 1, clearOld: true);
                                  _fetchSent(page: 1, clearOld: true);
                                }
                              });
                            },
                            onPreviewMessage: (msg) => _showPreviewDialog(msg, 'inbox'),
                          ),
                          SentTab(
                            isLoading: isLoadingSent,
                            isLoadingMore: isLoadingMoreSent,
                            errorMessage: errorSent,
                            messages: sentMessages,
                            scrollController: _sentScrollController,
                            hasMore: _hasMoreSent,
                            refreshInbox: () async {
                              _currentInboxPage = 1;
                              _hasMoreInbox = true;
                              await _fetchInbox(page: 1, clearOld: true);
                            },
                            refreshSent: () async {
                              _currentSentPage = 1;
                              _hasMoreSent = true;
                              await _fetchSent(page: 1, clearOld: true);
                            },
                            loadMore: _loadMoreSent,
                            onOpenMessage: (msg) {
                              Navigator.of(context)
                                  .push(MaterialPageRoute(
                                builder: (_) => MessageDetailScreen(
                                  messageLink: msg.link,
                                  folder: 'sent',
                                ),
                              ))
                                  .then((result) {
                                if (result == 'refresh' || result == 'marked_unread') {
                                  _fetchInbox(page: 1, clearOld: true);
                                  _fetchSent(page: 1, clearOld: true);
                                }
                              });
                            },
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

