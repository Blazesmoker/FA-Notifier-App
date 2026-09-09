import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/notes/domain/managed_notes_repository.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/domain/note_management.dart';
import 'package:fanotifier/features/notes/presentation/message_detail_screen.dart';
import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/presentation/time_display_settings_provider.dart';
import 'package:fanotifier/shared/utils/time_display_formatter.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:provider/provider.dart';

const double _selectionOpacity = 0.07;

class ManagedNotesFolderScreen extends StatefulWidget {
  const ManagedNotesFolderScreen({
    super.key,
    required this.folder,
  }) : assert(
          folder == NotesFolder.trash || folder == NotesFolder.archive,
        );

  final NotesFolder folder;

  @override
  State<ManagedNotesFolderScreen> createState() =>
      _ManagedNotesFolderScreenState();
}

class _ManagedNotesFolderScreenState extends State<ManagedNotesFolderScreen> {
  static const Color _accent = Color(0xFFE09321);
  static const int _selectAllRateLimitSeconds = 1;

  late final ManagedNotesRepository _repository;
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _errorMessage = '';
  List<Message> _messages = [];
  bool _isFetchingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isSelectAllInProgress = false;
  int _selectAllProgressPage = 0;
  bool _selectAllCancelled = false;
  bool _isMutating = false;

  bool get _isTrash => widget.folder == NotesFolder.trash;
  String get _title => _isTrash ? 'Trash' : 'Archive';

  @override
  void initState() {
    super.initState();
    _repository = context.read<ManagedNotesRepositoryFactory>()();
    _scrollController.addListener(_onScroll);
    _fetchFolder(page: 1);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100 &&
        !_isFetchingMore &&
        !_isSelectAllInProgress &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _fetchFolder({int page = 1, bool clearOld = false}) async {
    if (page == 1 && mounted) {
      setState(() {
        if (clearOld) _messages.clear();
        _isLoading = true;
        _errorMessage = '';
        _hasMore = true;
      });
    }

    try {
      final newMessages = await _repository.fetchFolderPage(
        folder: widget.folder,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        if (page == 1) {
          _messages = newMessages;
        } else {
          _messages.addAll(newMessages);
        }
        _isLoading = false;
        if (newMessages.isEmpty) _hasMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$e';
        _isLoading = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    _isFetchingMore = true;
    if (mounted) {
      setState(() {
        _isLoadingMore = true;
        _currentPage++;
      });
    }
    try {
      await _fetchFolder(page: _currentPage);
    } finally {
      _isFetchingMore = false;
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _enterSelectionModeAndSelect(Message message) {
    if (_isMutating) return;
    setState(() {
      _selectionMode = true;
      _selectedIds.add(message.id);
    });
  }

  void _toggleSelection(Message message) {
    if (_isMutating) return;
    setState(() {
      if (_selectedIds.contains(message.id)) {
        _selectedIds.remove(message.id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(message.id);
      }
    });
  }

  void _handleTapItem(Message message) {
    if (_selectionMode) {
      _toggleSelection(message);
      return;
    }
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        settings: const AnalyticsRouteSettings(AppScreens.noteDetails),
        builder: (_) => MessageDetailScreen(
          messageLink: message.link,
          folder: 'sent',
          sourceFolder: widget.folder,
          allowMarkUnread: false,
        ),
      ),
    )
        .then((result) {
      if (result == 'refresh' && mounted) {
        _currentPage = 1;
        _hasMore = true;
        _fetchFolder(page: 1);
      }
    });
  }

  void _selectAllLoaded() {
    if (_isSelectAllInProgress || _isMutating) return;
    setState(() {
      final loadedIds = _messages.map((message) => message.id).toSet();
      final allLoadedSelected = loadedIds.isNotEmpty &&
          loadedIds.every(_selectedIds.contains);
      if (allLoadedSelected) {
        _selectedIds.removeAll(loadedIds);
      } else {
        _selectedIds.addAll(loadedIds);
      }
    });
  }

  Future<void> _selectAllPages() async {
    if (_isSelectAllInProgress || _isMutating || _isFetchingMore) return;
    setState(() {
      _isSelectAllInProgress = true;
      _selectionMode = true;
      _selectedIds.clear();
      _selectAllProgressPage = 0;
      _selectAllCancelled = false;
    });

    final loadedIds = _messages.map((message) => message.id).toSet();
    var page = 1;
    while (mounted && !_selectAllCancelled) {
      setState(() => _selectAllProgressPage = page);
      List<Message> messages;
      try {
        messages = await _repository.fetchFolderPage(
          folder: widget.folder,
          page: page,
        );
      } catch (e) {
        if (mounted) {
          setState(() => _isSelectAllInProgress = false);
          _showSnackBar('Failed to fetch page $page.', success: false);
        }
        return;
      }

      if (messages.isEmpty) {
        if (mounted) setState(() => _hasMore = false);
        break;
      }
      if (!mounted) return;
      setState(() {
        for (final message in messages) {
          _selectedIds.add(message.id);
          if (loadedIds.add(message.id)) _messages.add(message);
        }
        if (page > _currentPage) _currentPage = page;
      });
      page++;
      await Future.delayed(
        const Duration(seconds: _selectAllRateLimitSeconds),
      );
    }

    if (mounted) setState(() => _isSelectAllInProgress = false);
  }

  void _cancelSelectAll() {
    _selectAllCancelled = true;
  }

  Future<void> _applySelectedAction(NoteManagementAction action) async {
    if (_selectedIds.isEmpty || _isSelectAllInProgress || _isMutating) return;
    final ids = _selectedIds.toList(growable: false);
    final copy = _actionCopy(action, ids.length);
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
      await _repository.applyAction(
        ids: ids,
        sourceFolder: widget.folder,
        action: action,
      );
      if (!mounted) return;
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
        _currentPage = 1;
        _hasMore = true;
      });
      await _fetchFolder(page: 1);
      if (mounted) _showSnackBar(copy.success, success: true);
    } on NoteManagementOutcomeUnknownException {
      if (mounted) _showSnackBar(copy.unknown, success: false);
    } catch (e) {
      if (mounted) _showSnackBar(copy.failure, success: false);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  _ManagedActionCopy _actionCopy(
    NoteManagementAction action,
    int count,
  ) {
    final notes = count == 1 ? 'note' : 'notes';
    final wasWere = count == 1 ? 'was' : 'were';
    return switch (action) {
      NoteManagementAction.moveToTrash => _ManagedActionCopy(
          title: 'Move to Trash',
          confirmation: 'Move $count $notes to Trash?',
          confirmLabel: 'Trash',
          success: 'Moved $count $notes to Trash.',
          failure: 'Failed to move $count $notes to Trash.',
          unknown:
              'Could not confirm whether $count $notes $wasWere moved to Trash.',
        ),
      NoteManagementAction.moveToArchive => _ManagedActionCopy(
          title: 'Move to Archive',
          confirmation: 'Move $count $notes to Archive?',
          confirmLabel: 'Archive',
          success: 'Moved $count $notes to Archive.',
          failure: 'Failed to move $count $notes to Archive.',
          unknown:
              'Could not confirm whether $count $notes $wasWere moved to Archive.',
        ),
      NoteManagementAction.restoreFromTrash => _ManagedActionCopy(
          title: 'Restore Notes',
          confirmation: 'Restore $count $notes to Inbox?',
          confirmLabel: 'Restore',
          success: 'Restored $count $notes to Inbox.',
          failure: 'Failed to restore $count $notes to Inbox.',
          unknown:
              'Could not confirm whether $count $notes $wasWere restored to Inbox.',
        ),
      NoteManagementAction.restoreFromArchive => _ManagedActionCopy(
          title: 'Restore Notes',
          confirmation: 'Restore $count $notes to Inbox?',
          confirmLabel: 'Restore',
          success: 'Restored $count $notes to Inbox.',
          failure: 'Failed to restore $count $notes to Inbox.',
          unknown:
              'Could not confirm whether $count $notes $wasWere restored to Inbox.',
        ),
      NoteManagementAction.deletePermanently => _ManagedActionCopy(
          title: 'Delete Permanently',
          confirmation:
              'Permanently delete $count selected $notes? This cannot be undone.',
          confirmLabel: 'Delete',
          success: 'Permanently deleted $count $notes.',
          failure: 'Failed to permanently delete $count $notes.',
          unknown:
              'Could not confirm whether $count $notes $wasWere permanently deleted.',
        ),
      NoteManagementAction.markUnread => throw ArgumentError.value(action),
    };
  }

  void _showSnackBar(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  void _exitSelectionMode() {
    if (_isSelectAllInProgress || _isMutating) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Widget _buildActionIcon({
    required IconData icon,
    required Color enabledColor,
    required VoidCallback onPressed,
  }) {
    final enabled = _selectedIds.isNotEmpty &&
        !_isSelectAllInProgress &&
        !_isMutating;
    return InkResponse(
      onTap: enabled ? onPressed : null,
      radius: 18,
      child: Icon(icon, color: enabled ? enabledColor : Colors.grey),
    );
  }

  Widget _buildSelectionBar() {
    final controlsDisabled = _isSelectAllInProgress || _isMutating;
    final allPagesDisabled = controlsDisabled || _isFetchingMore;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black,
      child: Row(
        children: [
          InkResponse(
            onTap: controlsDisabled ? null : _selectAllLoaded,
            radius: 18,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Text(
              'Select All (${_selectedIds.length})',
              style: TextStyle(
                color: controlsDisabled ? Colors.grey : _accent,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          InkResponse(
            onTap: allPagesDisabled ? null : _selectAllPages,
            radius: 18,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Text(
              'Select All Pages',
              style: TextStyle(
                color: allPagesDisabled ? Colors.grey : _accent,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkResponse(
            onTap: controlsDisabled ? null : _exitSelectionMode,
            radius: 18,
            child: Icon(
              Icons.close,
              color: controlsDisabled ? Colors.grey : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (_isTrash) {
      return [
        if (_selectionMode) ...[
          _buildActionIcon(
            icon: Icons.archive_outlined,
            enabledColor: Colors.white,
            onPressed: () => _applySelectedAction(
              NoteManagementAction.moveToArchive,
            ),
          ),
          const SizedBox(width: 16),
        ],
        _buildActionIcon(
          icon: Icons.restore,
          enabledColor: Colors.white,
          onPressed: () => _applySelectedAction(
            NoteManagementAction.restoreFromTrash,
          ),
        ),
        const SizedBox(width: 16),
        _buildActionIcon(
          icon: Icons.delete_forever,
          enabledColor: _accent,
          onPressed: () => _applySelectedAction(
            NoteManagementAction.deletePermanently,
          ),
        ),
        const SizedBox(width: 16),
      ];
    }
    return [
      if (_selectionMode) ...[
        _buildActionIcon(
          icon: Icons.delete_outline,
          enabledColor: Colors.white,
          onPressed: () => _applySelectedAction(
            NoteManagementAction.moveToTrash,
          ),
        ),
        const SizedBox(width: 16),
      ],
      _buildActionIcon(
        icon: Icons.restore,
        enabledColor: _accent,
        onPressed: () => _applySelectedAction(
          NoteManagementAction.restoreFromArchive,
        ),
      ),
      const SizedBox(width: 16),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selectionMode && !_isMutating,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode && !_isSelectAllInProgress) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          centerTitle: true,
          backgroundColor: Colors.black,
          actions: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: _buildAppBarActions(),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _selectionMode
                  ? _buildSelectionBar()
                  : const SizedBox.shrink(),
              if (_isSelectAllInProgress)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: Colors.grey[850],
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(_accent),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Fetching page $_selectAllProgressPage… ($_selectAllRateLimitSeconds s between requests)',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      InkResponse(
                        onTap: _cancelSelectAll,
                        radius: 18,
                        child: const Icon(
                          Icons.close,
                          color: Colors.red,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _ManagedNotesMessageList(
                  folderTitle: _title,
                  timeDisplayOccasion: _isTrash
                      ? TimeDisplayOccasion.notesTrash
                      : TimeDisplayOccasion.notesArchive,
                  isLoading: _isLoading,
                  isLoadingMore: _isLoadingMore,
                  errorMessage: _errorMessage,
                  messages: _messages,
                  scrollController: _scrollController,
                  hasMore: _hasMore,
                  onRefresh: () async {
                    _currentPage = 1;
                    _hasMore = true;
                    await _fetchFolder(page: 1);
                  },
                  isSelectionMode: _selectionMode,
                  selectedIds: _selectedIds,
                  onLongPressItem: _enterSelectionModeAndSelect,
                  onTapItem: _handleTapItem,
                  selectionOpacity: _selectionOpacity,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagedActionCopy {
  const _ManagedActionCopy({
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

class _ManagedNotesMessageList extends StatelessWidget {
  static const Color _accent = Color(0xFFE09321);

  const _ManagedNotesMessageList({
    required this.folderTitle,
    required this.timeDisplayOccasion,
    required this.isLoading,
    required this.isLoadingMore,
    required this.errorMessage,
    required this.messages,
    required this.scrollController,
    required this.hasMore,
    required this.onRefresh,
    required this.isSelectionMode,
    required this.selectedIds,
    required this.onLongPressItem,
    required this.onTapItem,
    required this.selectionOpacity,
  });

  final String folderTitle;
  final TimeDisplayOccasion timeDisplayOccasion;
  final bool isLoading;
  final bool isLoadingMore;
  final String errorMessage;
  final List<Message> messages;
  final ScrollController scrollController;
  final bool hasMore;
  final Future<void> Function() onRefresh;
  final bool isSelectionMode;
  final Set<String> selectedIds;
  final void Function(Message message) onLongPressItem;
  final void Function(Message message) onTapItem;
  final double selectionOpacity;

  @override
  Widget build(BuildContext context) {
    final timeFormat =
        context.select<TimeDisplaySettingsProvider, TimeDisplayFormat>(
      (settings) => settings.formatFor(timeDisplayOccasion),
    );
    if (isLoading && messages.isEmpty) {
      return RefreshIndicator(
        color: _accent,
        backgroundColor: Colors.black,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Center(
              child: PulsatingLoadingIndicator(
                size: 108,
                assetPath: 'assets/icons/fathemed.png',
              ),
            ),
          ],
        ),
      );
    }

    if (errorMessage.isNotEmpty && messages.isEmpty) {
      return RefreshIndicator(
        color: _accent,
        backgroundColor: Colors.black,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Center(
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    if (messages.isEmpty) {
      return RefreshIndicator(
        color: _accent,
        backgroundColor: Colors.black,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Center(
              child: Text(
                'No messages in $folderTitle.',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _accent,
      backgroundColor: Colors.black,
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: messages.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 44),
              child: Center(
                child: isLoadingMore
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation<Color>(_accent),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }

          final message = messages[index];
          final isSelected = selectedIds.contains(message.id);
          final otherParty = message.recipient.isNotEmpty
              ? message.recipient
              : message.sender;
          return GestureDetector(
            onLongPress: () => onLongPressItem(message),
            onTap: () => onTapItem(message),
            child: Column(
              children: [
                Container(
                  color: isSelected
                      ? _accent.withValues(alpha: selectionOpacity)
                      : Colors.black,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  child: Row(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: isSelectionMode
                            ? _buildCheckbox(message)
                            : const SizedBox.shrink(),
                      ),
                      if (message.isUnread)
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _accent,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.subject,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'To/From: $otherParty',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Date: ${formatTimeInText(
                                    message.date,
                                    format: timeFormat,
                                  )}',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildCheckbox(Message message) {
    final isSelected = selectedIds.contains(message.id);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: IgnorePointer(
        child: SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: isSelected,
            onChanged: (_) {},
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (isSelected) return _accent;
              return Colors.transparent;
            }),
            checkColor: Colors.white,
            side: BorderSide(
              color: isSelected ? _accent : Colors.grey,
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
