import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/notes/presentation/notes_selection_controls.dart';
import 'package:fanotifier/features/notes/presentation/notes_selection_layout.dart';
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
import 'managed_notes_folder_controller.dart';

const double _selectionOpacity = 0.08;

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

  late final ManagedNotesFolderController _folderController;
  final ScrollController _scrollController = ScrollController();

  bool get _isLoading => _folderController.isLoading;
  bool get _isLoadingMore => _folderController.isLoadingMore;
  String get _errorMessage => _folderController.errorMessage;
  bool get _isFetchingMore => _folderController.isFetchingMore;
  bool get _hasMore => _folderController.hasMore;
  bool get _selectionMode => _folderController.selectionMode;
  bool get _isSelectAllInProgress => _folderController.isSelectAllInProgress;
  int get _selectAllProgressPage => _folderController.selectAllProgressPage;
  bool get _isMutating => _folderController.isMutating;
  List<Message> get _messages => _folderController.messages;
  Set<String> get _selectedIds => _folderController.selectedIds;

  bool get _isTrash => widget.folder == NotesFolder.trash;
  String get _title => _isTrash ? 'Trash' : 'Archive';

  @override
  void initState() {
    super.initState();
    _folderController = ManagedNotesFolderController(
      repository: context.read<ManagedNotesRepositoryFactory>()(),
      folder: () => widget.folder,
      isMounted: () => mounted,
      updateState: (update) => setState(update),
      showSnackBar: _showSnackBar,
    );
    _scrollController.addListener(_onScroll);
    _folderController.fetchFolder(page: 1);
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
      _folderController.loadMore();
    }
  }

  void _handleTapItem(Message message) {
    if (_selectionMode) {
      _folderController.toggleSelection(message);
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
        _folderController.resetPagination();
        _folderController.fetchFolder(page: 1);
      }
    });
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

    await _folderController.applyAction(
      ids: ids,
      action: action,
      successMessage: copy.success,
      unknownMessage: copy.unknown,
      failureMessage: copy.failure,
    );
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
    return NotesSelectionControls(
      selectedCount: _selectedIds.length,
      onSelectAll: controlsDisabled ? null : _folderController.selectAllLoaded,
      onExit: controlsDisabled ? null : _folderController.exitSelectionMode,
      showAllPages: true,
      onSelectAllPages: allPagesDisabled ? null : _folderController.selectAllPages,
      progressText: _isSelectAllInProgress
          ? 'Fetching page $_selectAllProgressPage… (${ManagedNotesFolderController.selectAllRateLimitSeconds} s between requests)'
          : null,
      onCancelFetching: _folderController.cancelSelectAll,
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
          _folderController.exitSelectionMode();
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ManagedNotesMessageList(
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
                  _folderController.resetPagination();
                  await _folderController.fetchFolder(page: 1);
                },
                isSelectionMode: _selectionMode,
                selectedIds: _selectedIds,
                onLongPressItem: _folderController.enterSelectionModeAndSelect,
                onTapItem: _handleTapItem,
                selectionOpacity: _selectionOpacity,
                bottomPadding: !_selectionMode
                    ? 0
                    : _isSelectAllInProgress
                        ? NotesSelectionControls.progressBottomClearance
                        : NotesSelectionControls.bottomClearance,
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
    required this.bottomPadding,
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
  final double bottomPadding;

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
        padding: EdgeInsets.only(bottom: bottomPadding),
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
                  child: NotesSelectionLayout(
                    isSelectionMode: isSelectionMode,
                    rowBuilder: (selecting) => Row(
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: selecting
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
                          child: NotesSelectionContent(
                            selecting: selecting,
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
                        ),
                      ],
                    ),
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
