import 'dart:async';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:FANotifier/app/navigation/app_navigation.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/notes/presentation/message_detail_screen.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/features/notes/domain/notes_repository.dart';
import 'package:FANotifier/features/notes/presentation/new_message.dart';
import 'package:FANotifier/features/drawer/presentation/drawer_user_controller.dart';
import 'package:FANotifier/features/notes/domain/notes_screen_view_state.dart';
import 'package:FANotifier/features/notes/presentation/notesscreen_preview_dialog.dart';
import 'package:FANotifier/features/notes/presentation/notesscreen_inbox.dart';
import 'package:FANotifier/features/notes/presentation/notesscreen_sent.dart';
import 'package:FANotifier/features/notes/presentation/notes_screen_controller.dart';
import 'package:FANotifier/features/notes/presentation/trash_screen.dart';

class NotesScreen extends StatefulWidget {
  final GlobalKey<DrawerUserControllerState> drawerKey;
  final bool forceRefresh;
  final NotesRepository Function() repositoryFactory;

  NotesScreen({
    Key? key,
    required this.drawerKey,
    required this.repositoryFactory,
    this.forceRefresh = false,
  }) : super(key: key);

  @override
  NotesScreenState createState() => NotesScreenState();
}

class NotesScreenState extends State<NotesScreen>
    with RouteAware, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFFE09321);

  late final NotesScreenController _notesController;
  late final TabController _tabController;

  StreamSubscription<void>? _notesRefreshSub;
  bool _isVisibleInHomeStack = false;
  AppLifecycleState? _lastLifecycleState;

  bool _isDialogOpen = false;

  final ScrollController _inboxScrollController = ScrollController();
  final ScrollController _sentScrollController = ScrollController();

  bool _isDraggingFromEdge = false;
  int _prevTabIndex = 0;

  NotesScreenViewState get _notesState => _notesController.state;
  bool get isLoadingInbox => _notesState.isLoadingInbox;
  bool get isLoadingMoreInbox => _notesState.isLoadingMoreInbox;
  String get errorInbox => _notesState.errorInbox;
  List<Message> get inboxMessages => _notesState.inboxMessages;
  bool get _hasMoreInbox => _notesState.hasMoreInbox;
  bool get isLoadingSent => _notesState.isLoadingSent;
  bool get isLoadingMoreSent => _notesState.isLoadingMoreSent;
  String get errorSent => _notesState.errorSent;
  List<Message> get sentMessages => _notesState.sentMessages;
  bool get _hasMoreSent => _notesState.hasMoreSent;
  bool get _selectionMode => _notesState.isSelectionMode;
  Set<String> get _selectedIds => _notesState.selectedIds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notesController = NotesScreenController(
      repository: widget.repositoryFactory(),
      updateState: (update) => setState(update),
    );
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);

    if (widget.forceRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _notesController.resetAllPagination();
        await _fetchInbox(page: 1, clearOld: false);
        await _refreshSentIfVisibleOrMarkStale();
      });
    }

    _notesController.initialize().then((_) {
      _initInboxAndSent();
    });

    _notesRefreshSub = _notesController.refreshStream.listen((_) {
      _refreshFromSignal();
    });
    if (_notesController.takePendingRefresh()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshFromSignal();
      });
    }
  }

  void _refreshFromSignal() {
    if (!mounted) return;
    _notesController.resetAllPagination();
    _fetchInbox(page: 1, clearOld: false);
    _refreshSentIfVisibleOrMarkStale();
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (_tabController.index == 1) {
      _ensureSentLoaded();
    }
    if (!_tabController.indexIsChanging &&
        _tabController.index != _prevTabIndex) {
      _prevTabIndex = _tabController.index;
      _notesController.clearSelection();
    }
  }

  Future<void> _refreshSentIfVisibleOrMarkStale() async {
    await _notesController.refreshSentIfVisibleOrMarkStale(
      sentVisible: _tabController.index == 1,
    );
  }

  Future<void> _ensureSentLoaded({bool force = false}) async {
    await _notesController.ensureSentLoaded(force: force);
  }

  void _enterSelectionModeAndSelect(Message msg) {
    _notesController.enterSelectionModeAndSelect(msg);
  }

  void _toggleSelection(Message msg) {
    _notesController.toggleSelection(msg);
  }

  void _handleTapItem(Message msg) {
    if (_selectionMode) {
      _toggleSelection(msg);
    } else {
      if (_tabController.index == 0) {
        Navigator.of(context)
            .push(MaterialPageRoute(
          builder: (_) => MessageDetailScreen(
            messageLink: msg.link,
            folder: 'inbox',
          ),
        ))
            .then((result) {
          if (result == 'refresh' || result == 'marked_unread') {
            _refreshAfterMessageMutation();
          }
        });
      } else {
        Navigator.of(context)
            .push(MaterialPageRoute(
          builder: (_) => MessageDetailScreen(
            messageLink: msg.link,
            folder: 'sent',
          ),
        ))
            .then((result) {
          if (result == 'refresh' || result == 'marked_unread') {
            _refreshAfterMessageMutation();
          }
        });
      }
    }
  }

  void _refreshAfterMessageMutation() {
    _notesController.resetAllPagination();
    _fetchInbox(page: 1, clearOld: false);
    _refreshSentIfVisibleOrMarkStale();
  }

  Future<void> _trashSelected() async {
    if (_selectedIds.isEmpty) return;
    final folder = _tabController.index == 0 ? 'inbox' : 'sent';
    final ids = _selectedIds.toList();
    try {
      await _notesController.moveNotesToTrash(ids: ids, folder: folder);
      if (!mounted) return;
      _notesController.clearSelection();
      await _notesController.refreshAfterTrash(folder);
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

    _inboxScrollController.dispose();
    _sentScrollController.dispose();
    _notesRefreshSub?.cancel();
    _notesController.setScreenVisible(false);
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
      _notesController.resetSentPagination();
      _refreshSentIfVisibleOrMarkStale();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final prev = _lastLifecycleState;
    _lastLifecycleState = state;

    if (state == AppLifecycleState.resumed && mounted && !_isDialogOpen) {
      // Android notification shade can cause inactive -> resumed.
      // Don't treat that as a real resume that should refetch.
      if (prev == AppLifecycleState.inactive) {
        return;
      }
      // Only auto-refetch on resume if Notes is visible (selected).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDialogOpen || !_isVisibleInHomeStack) return;
        _notesController.clearErrorsWithoutNotification();
        _notesController.resetAllPagination();
        _fetchInbox(page: 1, clearOld: false);
        _refreshSentIfVisibleOrMarkStale();
      });
    }
  }

  void _initInboxAndSent() {
    _inboxScrollController.addListener(() {
      if (_inboxScrollController.position.pixels ==
              _inboxScrollController.position.maxScrollExtent &&
          !_notesController.isFetchingMoreInbox &&
          _hasMoreInbox) {
        _loadMoreInbox();
      }
    });

    _sentScrollController.addListener(() {
      if (_sentScrollController.position.pixels ==
              _sentScrollController.position.maxScrollExtent &&
          !_notesController.isFetchingMoreSent &&
          _hasMoreSent) {
        _loadMoreSent();
      }
    });

    _fetchInbox(page: 1);
  }

  Future<void> _fetchInboxTwoPagesOnly() async {
    await _notesController.fetchInboxTwoPagesOnly();
  }

  Future<void> _fetchInbox({
    int page = 1,
    bool clearOld = false,
    bool suppressNewUnreadNotifications = false,
  }) async {
    await _notesController.fetchInbox(
      page: page,
      clearOld: clearOld,
      suppressNewUnreadNotifications: suppressNewUnreadNotifications,
    );
  }

  Future<void> _loadMoreInbox() async {
    await _notesController.loadMoreInbox();
  }

  Future<void> _fetchSent({int page = 1, bool clearOld = false}) async {
    await _notesController.fetchSent(page: page, clearOld: clearOld);
  }

  Future<void> _loadMoreSent() async {
    await _notesController.loadMoreSent();
  }

  Future<void> _markAsUnreadWithoutRefetch(Message msg) async {
    await _notesController.markAsUnreadWithoutRefetch(msg);
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
        title:
            const Text('Move to Trash', style: TextStyle(color: Colors.white)),
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
            child: const Text('Trash',
                style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) _trashSelected();
    });
  }

  void exitSelectionMode() {
    _notesController.clearSelection();
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
      barrierDismissible: true,
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
    return VisibilityDetector(
      key: const Key('notes_screen_visibility'),
      onVisibilityChanged: (info) {
        _isVisibleInHomeStack = info.visibleFraction > 0.01;
        _notesController.setScreenVisible(_isVisibleInHomeStack);
      },
      child: _buildNotesScaffold(context),
    );
  }

  Widget _buildNotesScaffold(BuildContext context) {
    final bool showInitialLoader = (inboxMessages.isEmpty && isLoadingInbox) &&
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
                          MaterialPageRoute(
                              builder: (_) => const TrashScreen()),
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
                      _notesController.resetInboxPagination();
                      await _fetchInbox(page: 1, clearOld: false);
                    },
                    refreshSent: () async {
                      _notesController.resetSentPagination();
                      await _refreshSentIfVisibleOrMarkStale();
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
                          _refreshAfterMessageMutation();
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
                      _notesController.resetInboxPagination();
                      await _fetchInbox(page: 1, clearOld: false);
                    },
                    refreshSent: () async {
                      _notesController.resetSentPagination();
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
                          _refreshAfterMessageMutation();
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
