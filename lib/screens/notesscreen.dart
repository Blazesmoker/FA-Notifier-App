import 'dart:async';
import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../main.dart';
import 'package:FANotifier/services/notes_refresh_service.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'message_detail_screen.dart';
import 'message_model.dart';
import 'new_message.dart';
import '../services/notification_service.dart';
import '../services/fa_http.dart';
import '../utils/message_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../custom_drawer/drawer_user_controller.dart';
import 'notesscreen_api_service.dart';
import 'notesscreen_preview_dialog.dart';
import 'notesscreen_inbox.dart';
import 'notesscreen_sent.dart';
import 'trash_screen.dart';

class NotesScreen extends StatefulWidget {
  final GlobalKey<DrawerUserControllerState> drawerKey;
  final bool forceRefresh;

  NotesScreen({
    Key? key,
    required this.drawerKey,
    this.forceRefresh = false,
  }) : super(key: key);

  @override
  NotesScreenState createState() => NotesScreenState();
}

class NotesScreenState extends State<NotesScreen>
    with RouteAware, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFFE09321);

  final _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  late final NotesApiService _notesApi;
  late final TabController _tabController;

  Timer? _refreshTimer;
  StreamSubscription<void>? _notesRefreshSub;
  bool _isVisibleInHomeStack = false;
  AppLifecycleState? _lastLifecycleState;
  bool _iosForegroundTimerSuspended = false;

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

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  int _prevTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notesApi = NotesApiService(_secureStorage);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);

    if (widget.forceRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _currentInboxPage = 1;
        _currentSentPage = 1;
        _hasMoreInbox = true;
        _hasMoreSent = true;
        await _fetchInbox(page: 1, clearOld: false);
        await _fetchSent(page: 1, clearOld: false);
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
      _currentInboxPage = 1;
      _currentSentPage = 1;
      _hasMoreInbox = true;
      _hasMoreSent = true;
      _fetchInbox(page: 1, clearOld: false);
      _fetchSent(page: 1, clearOld: false);
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && mounted &&
        _tabController.index != _prevTabIndex) {
      _prevTabIndex = _tabController.index;
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
    }
  }

  void _enterSelectionModeAndSelect(Message msg) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(msg.id);
    });
  }

  void _toggleSelection(Message msg) {
    setState(() {
      if (_selectedIds.contains(msg.id)) {
        _selectedIds.remove(msg.id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(msg.id);
      }
    });
  }

  void _handleTapItem(Message msg) {
    if (_selectionMode) {
      _toggleSelection(msg);
    } else {
      if (_tabController.index == 0) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MessageDetailScreen(
            messageLink: msg.link,
            folder: 'inbox',
          ),
        )).then((result) {
          if (result == 'refresh' || result == 'marked_unread') {
            _currentInboxPage = 1;
            _currentSentPage = 1;
            _hasMoreInbox = true;
            _hasMoreSent = true;
            _fetchInbox(page: 1, clearOld: false);
            _fetchSent(page: 1, clearOld: false);
          }
        });
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MessageDetailScreen(
            messageLink: msg.link,
            folder: 'sent',
          ),
        )).then((result) {
          if (result == 'refresh' || result == 'marked_unread') {
            _currentInboxPage = 1;
            _currentSentPage = 1;
            _hasMoreInbox = true;
            _hasMoreSent = true;
            _fetchInbox(page: 1, clearOld: false);
            _fetchSent(page: 1, clearOld: false);
          }
        });
      }
    }
  }

  Future<void> _trashSelected() async {
    if (_selectedIds.isEmpty) return;
    final folder = _tabController.index == 0 ? 'inbox' : 'sent';
    final ids = _selectedIds.toList();
    try {
      await _notesApi.moveNotesToTrash(ids: ids, folder: folder);
      if (!mounted) return;
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      if (folder == 'inbox') {
        _currentInboxPage = 1;
        _hasMoreInbox = true;
        await _fetchInbox(
          page: 1,
          clearOld: false,
          suppressNewUnreadNotifications: true,
        );
        try {
          final page2Messages = await _notesApi.fetchNotesPage(folder: 'inbox', page: 2);
          final unread = page2Messages.where((m) => m.isUnread).toList();
          if (unread.isNotEmpty) {
            final unreadIds = unread.map((m) => m.id).toList();
            await MessageStorage.addShownNoteIds(unreadIds);
          }
        } catch (e) {
          debugPrint('[_trashSelected] Failed to pre-mark page 2: $e');
        }
      } else {
        _currentSentPage = 1;
        _hasMoreSent = true;
        await _fetchSent(page: 1, clearOld: false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to move to Trash: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);

    _tabController.dispose();

    _refreshTimer?.cancel();
    _inboxScrollController.dispose();
    _sentScrollController.dispose();
    _notesRefreshSub?.cancel();
    super.dispose();
  }

  Future<void> scrollToTop({bool animate = true}) async {
    final controller = (_tabController.index == 0)
        ? _inboxScrollController
        : _sentScrollController;
    if (!controller.hasClients) return;
    if (!animate) {
      controller.jumpTo(0);
      return;
    }
    await controller.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    // NotesScreen lives inside HomeScreen's IndexedStack, so it stays mounted even
    // when another tab is selected. Only refetch on returning to Home if Notes is
    // actually visible (selected).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDialogOpen || !_isVisibleInHomeStack) return;
      _fetchInboxTwoPagesOnly();
      _currentSentPage = 1;
      _hasMoreSent = true;
      _fetchSent(page: 1, clearOld: false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final prev = _lastLifecycleState;
    _lastLifecycleState = state;

    if (Platform.isIOS &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused)) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _iosForegroundTimerSuspended = true;
      return;
    }

    if (state == AppLifecycleState.resumed && mounted && !_isDialogOpen) {
      if (Platform.isIOS && _iosForegroundTimerSuspended) {
        if (prev == AppLifecycleState.inactive) {
          _iosForegroundTimerSuspended = false;
          _startPeriodicFetch();
          return;
        }
        _iosForegroundTimerSuspended = false;
      }
      // Android notification shade can cause inactive -> resumed.
      // Don't treat that as a real resume that should refetch.
      if (prev == AppLifecycleState.inactive) {
        return;
      }
      // Only auto-refetch on resume if Notes is visible (selected).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDialogOpen || !_isVisibleInHomeStack) return;
        errorInbox = '';
        errorSent = '';
        _currentInboxPage = 1;
        _currentSentPage = 1;
        _hasMoreInbox = true;
        _hasMoreSent = true;
        _fetchInbox(page: 1, clearOld: false);
        _fetchSent(page: 1, clearOld: false);

        _startPeriodicFetch();
      });
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
    _refreshTimer = Timer.periodic(const Duration(seconds: 200), (_) {
      if (mounted && !_isDialogOpen) {
        _fetchInboxTwoPagesOnly();
      }
    });
  }

  Future<void> _fetchInboxTwoPagesOnly() async {
    try {
      List<Message> newFetched = [];
      newFetched
          .addAll(await _notesApi.fetchNotesPage(folder: 'inbox', page: 1));
      newFetched
          .addAll(await _notesApi.fetchNotesPage(folder: 'inbox', page: 2));
      await _handleNewUnreadMessages(newFetched);
    } catch (e) {
      debugPrint('[Foreground fetchInboxTwoPagesOnly] error => $e');
    }
  }

  Future<void> _fetchInbox({
    int page = 1,
    bool clearOld = false,
    bool suppressNewUnreadNotifications = false,
  }) async {
    if (page == 1) {
      setState(() {
        if (clearOld) inboxMessages.clear();
        isLoadingInbox = true;
        errorInbox = '';
        _hasMoreInbox = true;
      });
    }

    try {
      final newMessages =
      await _notesApi.fetchNotesPage(folder: 'inbox', page: page);

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

      if (page == 1 && !suppressNewUnreadNotifications) {
        await _handleNewUnreadMessages(newMessages);
      } else {
        final unread = newMessages.where((m) => m.isUnread).toList();
        if (unread.isNotEmpty) {
          final unreadIds = unread.map((m) => m.id).toList();
          await MessageStorage.addShownNoteIds(unreadIds);
        }
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
      final newMessages =
      await _notesApi.fetchNotesPage(folder: 'sent', page: page);

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

      final newUnread = unread.where((m) => !shownIds.contains(m.id)).toList();
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
            'User-Agent': FAHttp.userAgent,
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://www.furaffinity.net/msg/pms/$pageNum/$msgId/',
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

  void _openNewMessage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewMessageScreen()),
    );
  }

  void _onTrashPressed() {
    if (_selectedIds.isEmpty) return;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Move to Trash', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to send selected Notes to Trash folder?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Trash', style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) _trashSelected();
    });
  }

  void exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  bool get isInSelectionMode => _selectionMode;

  Widget _buildNewMessageAppBarButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 20.0),
      child: Semantics(
        button: true,
        label: 'New message',
        child: Material(
          color: _accent,
          shape: const CircleBorder(),
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _openNewMessage,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Icon(Icons.mail, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
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
    // Track whether Notes is actually visible (selected) in HomeScreen's IndexedStack.
    // This prevents RouteAware callbacks from triggering network requests while hidden.
    //
    // Note: visibility_detector is already used elsewhere in the app.
    // We keep periodic fetch behavior unchanged per request.
    return VisibilityDetector(
      key: const Key('notes_screen_visibility'),
      onVisibilityChanged: (info) {
        _isVisibleInHomeStack = info.visibleFraction > 0.01;
      },
      child: _buildNotesScaffold(context),
    );
  }

  Widget _buildNotesScaffold(BuildContext context) {
    final bool showInitialLoader =
        (inboxMessages.isEmpty && isLoadingInbox) &&
            (sentMessages.isEmpty && isLoadingSent);

    if (showInitialLoader) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notes'),
          centerTitle: true,
          backgroundColor: Colors.black,
          actions: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 52),
                InkResponse(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TrashScreen()),
                    );
                  },
                  radius: 18,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                const SizedBox(width: 16),
              ],
            ),
            _buildNewMessageAppBarButton(),
          ],
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

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Notes'),
            centerTitle: true,
            backgroundColor: Colors.black,
            actions: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 52,
                    child: _selectionMode
                        ? InkResponse(
                            onTap: exitSelectionMode,
                            radius: 18,
                            child: const Icon(Icons.close, color: Colors.white),
                          )
                        : const SizedBox.shrink(),
                  ),

                  InkResponse(
                    onTap: () {
                      if (_selectionMode && _selectedIds.isNotEmpty) {
                        _onTrashPressed();
                      } else if (!_selectionMode) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TrashScreen()),
                        );
                      }
                    },
                    radius: 18,
                    child: Icon(
                      Icons.delete_outline,
                      color: _selectionMode && _selectedIds.isEmpty
                          ? Colors.grey
                          : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 18),
                ],
              ),
              _buildNewMessageAppBarButton(),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicator: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(width: 2.5, color: _accent),
                ),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: const TextStyle(
                fontSize: 19.0,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 17.0),
              tabs: const [
                Tab(text: 'Inbox'),
                Tab(text: 'Sent'),
              ],
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0.0),
            child: NotificationListener<OverscrollNotification>(
              onNotification: (OverscrollNotification notification) {
                final tabIndex = _tabController.index;
                if (tabIndex == 0 &&
                    notification.metrics.axis == Axis.horizontal &&
                    notification.overscroll < 0) {
                  widget.drawerKey.currentState?.openDrawer();
                  return true;
                }
                return false;
              },
              child: TabBarView(
                controller: _tabController,
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
                      await _fetchInbox(page: 1, clearOld: false);
                    },
                    refreshSent: () async {
                      _currentSentPage = 1;
                      _hasMoreSent = true;
                      await _fetchSent(page: 1, clearOld: false);
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
                          _currentInboxPage = 1;
                          _currentSentPage = 1;
                          _hasMoreInbox = true;
                          _hasMoreSent = true;
                          _fetchInbox(page: 1, clearOld: false);
                          _fetchSent(page: 1, clearOld: false);
                        }
                      });
                    },
                    onPreviewMessage: (msg) => _showPreviewDialog(msg, 'inbox'),
                    isSelectionMode: _selectionMode,
                    selectedIds: _selectedIds,
                    onLongPressItem: _enterSelectionModeAndSelect,
                    onTapItem: _handleTapItem,
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
                      await _fetchInbox(page: 1, clearOld: false);
                    },
                    refreshSent: () async {
                      _currentSentPage = 1;
                      _hasMoreSent = true;
                      await _fetchSent(page: 1, clearOld: false);
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
                          _currentInboxPage = 1;
                          _currentSentPage = 1;
                          _hasMoreInbox = true;
                          _hasMoreSent = true;
                          _fetchInbox(page: 1, clearOld: false);
                          _fetchSent(page: 1, clearOld: false);
                        }
                      });
                    },
                    isSelectionMode: _selectionMode,
                    selectedIds: _selectedIds,
                    onLongPressItem: _enterSelectionModeAndSelect,
                    onTapItem: _handleTapItem,
                  ),
                ],
              ),
            ),
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
    );
  }
}
