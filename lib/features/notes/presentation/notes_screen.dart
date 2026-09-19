import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:fanotifier/core/analytics/app_analytics.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/features/notes/presentation/message_detail_screen.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/domain/note_management.dart';
import 'package:fanotifier/features/notes/domain/notes_repository.dart';
import 'package:fanotifier/features/notes/presentation/archive_screen.dart';
import 'package:fanotifier/features/notes/presentation/new_message_screen.dart';
import 'package:fanotifier/features/drawer/presentation/home_drawer_shell.dart';
import 'package:fanotifier/features/notes/domain/notes_screen_view_state.dart';
import 'package:fanotifier/features/notes/presentation/note_preview_dialog.dart';
import 'package:fanotifier/features/notes/presentation/notes_inbox_tab.dart';
import 'package:fanotifier/features/notes/presentation/notes_sent_tab.dart';
import 'package:fanotifier/features/notes/presentation/notes_screen_controller.dart';
import 'package:fanotifier/features/notes/presentation/trash_screen.dart';
import 'package:fanotifier/features/notes/presentation/notes_selection_controls.dart';

enum _NotesMenuAction {
  trash,
  archive,
  markUnread,
}

class _NotesActionCopy {
  const _NotesActionCopy({
    required this.title,
    required this.confirmation,
    required this.confirmLabel,
    required this.success,
    required this.failure,
    required this.unknown,
  });

  final String title;
  final String confirmation;
  final String confirmLabel;
  final String success;
  final String failure;
  final String unknown;
}

class NotesScreen extends StatefulWidget {
  final GlobalKey<HomeDrawerShellState> drawerKey;
  final NotesRepository Function() repositoryFactory;

  const NotesScreen({
    super.key,
    required this.drawerKey,
    required this.repositoryFactory,
  });

  @override
  NotesScreenState createState() => NotesScreenState();
}

class NotesScreenState extends State<NotesScreen>
    with RouteAware, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFFE09321);
  static const double _notesActionSpacing = 6.0;
  static const double _notesMenuVerticalPadding = 12.0;

  late final NotesScreenController _notesController;
  late final TabController _tabController;

  StreamSubscription<void>? _notesRefreshSub;
  bool _isVisibleInHomeStack = false;
  bool _initialInboxLoadCompleted = false;
  AppLifecycleState? _lastLifecycleState;

  bool _isDialogOpen = false;
  bool _isMutating = false;

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
  bool get _hasLoadedSent => _notesController.hasLoadedSent;
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

    _notesRefreshSub = _notesController.refreshStream.listen((_) {
      if (!_initialInboxLoadCompleted) return;
      _refreshFromSignal();
    });
    _notesController.takePendingRefresh();

    _notesController.initialize().then((_) async {
      if (!mounted) return;
      await _initInboxAndSent();
      _initialInboxLoadCompleted = true;
    });
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
      appAnalytics.logScreen(
        _tabController.index == 0 ? AppScreens.notesInbox : AppScreens.notesSent,
      );
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
    if (_isMutating) return;
    _notesController.enterSelectionModeAndSelect(msg);
  }

  void _toggleSelection(Message msg) {
    if (_isMutating) return;
    _notesController.toggleSelection(msg);
  }

  void _selectAllLoadedMessages() {
    if (_isMutating) return;
    final messages =
        _tabController.index == 0 ? inboxMessages : sentMessages;
    _notesController.toggleSelectAll(messages);
  }

  void _handleTapItem(Message msg) {
    if (_isMutating) return;
    if (_selectionMode) {
      _toggleSelection(msg);
    } else {
      if (_tabController.index == 0) {
        Navigator.of(context)
            .push(MaterialPageRoute(
          settings: const AnalyticsRouteSettings(AppScreens.noteDetails),
          builder: (_) => MessageDetailScreen(
            messageLink: msg.link,
            folder: 'inbox',
            sourceFolder: NotesFolder.inbox,
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
          settings: const AnalyticsRouteSettings(AppScreens.noteDetails),
          builder: (_) => MessageDetailScreen(
            messageLink: msg.link,
            folder: 'sent',
            sourceFolder: NotesFolder.sent,
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

  Future<void> _applySelectedAction(_NotesMenuAction menuAction) async {
    if (_selectedIds.isEmpty || _isMutating) return;
    final sourceFolder = _tabController.index == 0
        ? NotesFolder.inbox
        : NotesFolder.sent;
    if (sourceFolder == NotesFolder.sent &&
        menuAction == _NotesMenuAction.markUnread) {
      return;
    }
    final ids = _selectedIds.toList(growable: false);
    final copy = _notesActionCopy(menuAction, ids.length);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(copy.title, style: const TextStyle(color: Colors.white)),
        content: Text(
          copy.confirmation,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              copy.confirmLabel,
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isMutating = true);
    try {
      await _notesController.applyManagementAction(
        ids: ids,
        sourceFolder: sourceFolder,
        action: switch (menuAction) {
          _NotesMenuAction.trash => NoteManagementAction.moveToTrash,
          _NotesMenuAction.archive => NoteManagementAction.moveToArchive,
          _NotesMenuAction.markUnread => NoteManagementAction.markUnread,
        },
      );
      if (!mounted) return;
      _notesController.clearSelection();
      if (menuAction == _NotesMenuAction.markUnread) {
        await _notesController.refreshAfterManualUnread(ids);
      } else {
        await _notesController.refreshAfterManagementAction(sourceFolder);
      }
      if (mounted) _showManagementSnackBar(copy.success, success: true);
    } on NoteManagementOutcomeUnknownException {
      if (mounted) _showManagementSnackBar(copy.unknown, success: false);
    } catch (e) {
      if (mounted) _showManagementSnackBar(copy.failure, success: false);
    } finally {
      if (mounted) setState(() => _isMutating = false);
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
        _fetchInbox(
          page: 1,
          clearOld: false,
          suppressNewUnreadNotifications: true,
        );
        _refreshSentIfVisibleOrMarkStale();
      });
    }
  }

  Future<void> _initInboxAndSent() async {
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

    await _fetchInbox(page: 1);
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
      MaterialPageRoute(
        settings: const AnalyticsRouteSettings(AppScreens.newNote),
        builder: (_) => NewMessageScreen(),
      ),
    );
  }

  void _handleNotesMenuAction(_NotesMenuAction action) {
    if (_selectionMode) {
      _applySelectedAction(action);
      return;
    }
    final screen = switch (action) {
      _NotesMenuAction.trash => const TrashScreen(),
      _NotesMenuAction.archive => const ArchiveScreen(),
      _NotesMenuAction.markUnread => null,
    };
    if (screen == null) return;
    final analyticsScreen = action == _NotesMenuAction.trash
        ? AppScreens.notesTrash
        : AppScreens.notesArchive;
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: AnalyticsRouteSettings(analyticsScreen),
        builder: (_) => screen,
      ),
    );
  }

  _NotesActionCopy _notesActionCopy(_NotesMenuAction action, int count) {
    final notes = count == 1 ? 'note' : 'notes';
    final wasWere = count == 1 ? 'was' : 'were';
    return switch (action) {
      _NotesMenuAction.trash => _NotesActionCopy(
          title: 'Move to Trash',
          confirmation: 'Move $count $notes to Trash?',
          confirmLabel: 'Trash',
          success: 'Moved $count $notes to Trash.',
          failure: 'Failed to move $count $notes to Trash.',
          unknown:
              'Could not confirm whether $count $notes $wasWere moved to Trash.',
        ),
      _NotesMenuAction.archive => _NotesActionCopy(
          title: 'Move to Archive',
          confirmation: 'Move $count $notes to Archive?',
          confirmLabel: 'Archive',
          success: 'Moved $count $notes to Archive.',
          failure: 'Failed to move $count $notes to Archive.',
          unknown:
              'Could not confirm whether $count $notes $wasWere moved to Archive.',
        ),
      _NotesMenuAction.markUnread => _NotesActionCopy(
          title: 'Mark as Unread',
          confirmation: 'Mark $count $notes as unread?',
          confirmLabel: 'Mark as Unread',
          success: 'Marked $count $notes as unread.',
          failure: 'Failed to mark $count $notes as unread.',
          unknown:
              'Could not confirm whether $count $notes $wasWere marked as unread.',
        ),
    };
  }

  void _showManagementSnackBar(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  void exitSelectionMode() {
    if (_isMutating) return;
    _notesController.clearSelection();
  }

  bool get isInSelectionMode => _selectionMode;

  Widget _buildSelectionBar() {
    return NotesSelectionControls(
      selectedCount: _selectedIds.length,
      onSelectAll: _isMutating ? null : _selectAllLoadedMessages,
      onExit: _isMutating ? null : exitSelectionMode,
    );
  }

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

  Widget _buildNotesManagementMenu() {
    return PopupMenuButton<_NotesMenuAction>(
      tooltip: 'Manage notes',
      position: PopupMenuPosition.under,
      offset: const Offset(-6, 8),
      menuPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF3A3A3A)),
      ),
      enabled: !_isMutating,
      onSelected: _handleNotesMenuAction,
      icon: Icon(
        Icons.edit_note,
        color: _isMutating ? Colors.grey : Colors.white,
      ),
      itemBuilder: (context) => [
        _buildNotesMenuItem(
          action: _NotesMenuAction.trash,
          icon: Icons.delete_outline,
          label: 'Trash',
        ),
        _buildNotesMenuDivider(),
        _buildNotesMenuItem(
          action: _NotesMenuAction.archive,
          icon: Icons.archive_outlined,
          label: 'Archive',
        ),
        if (_selectionMode && _tabController.index == 0) ...[
          _buildNotesMenuDivider(),
          _buildNotesMenuItem(
            action: _NotesMenuAction.markUnread,
            icon: Icons.mark_email_unread_outlined,
            label: 'Mark as Unread',
          ),
        ],
      ],
    );
  }

  PopupMenuItem<_NotesMenuAction> _buildNotesMenuItem({
    required _NotesMenuAction action,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<_NotesMenuAction>(
      value: action,
      height: 40,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: _notesMenuVerticalPadding,
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 21),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  PopupMenuItem<_NotesMenuAction> _buildNotesMenuDivider() {
    return const PopupMenuItem<_NotesMenuAction>(
      enabled: false,
      height: 1,
      padding: EdgeInsets.zero,
      child: Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFF3A3A3A),
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
          child: NotePreviewDialog(
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
                _buildNotesManagementMenu(),
                const SizedBox(width: _notesActionSpacing),
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
                  _buildNotesManagementMenu(),
                  const SizedBox(width: _notesActionSpacing),
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
          body: SafeArea(
            top: false,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
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
                        NotesInboxTab(
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
                              settings: const AnalyticsRouteSettings(
                                AppScreens.noteDetails,
                              ),
                              builder: (_) => MessageDetailScreen(
                                messageLink: msg.link,
                                folder: 'inbox',
                                sourceFolder: NotesFolder.inbox,
                              ),
                            ))
                                .then((result) {
                              if (result == 'refresh' ||
                                  result == 'marked_unread') {
                                _refreshAfterMessageMutation();
                              }
                            });
                          },
                          onPreviewMessage: (msg) =>
                              _showPreviewDialog(msg, 'inbox'),
                          isSelectionMode: _selectionMode,
                          selectedIds: _selectedIds,
                          onLongPressItem: _enterSelectionModeAndSelect,
                          onTapItem: _handleTapItem,
                        ),
                        NotesSentTab(
                          isLoading: isLoadingSent ||
                              (!_hasLoadedSent && errorSent.isEmpty),
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
                              settings: const AnalyticsRouteSettings(
                                AppScreens.noteDetails,
                              ),
                              builder: (_) => MessageDetailScreen(
                                messageLink: msg.link,
                                folder: 'sent',
                                sourceFolder: NotesFolder.sent,
                              ),
                            ))
                                .then((result) {
                              if (result == 'refresh' ||
                                  result == 'marked_unread') {
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
                if (_selectionMode)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildSelectionBar(),
                  ),
              ],
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
