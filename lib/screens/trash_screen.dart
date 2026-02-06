import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'message_detail_screen.dart';
import 'message_model.dart';
import 'notesscreen_api_service.dart';
import 'notesscreen_widgets.dart';
import '../widgets/PulsatingLoadingIndicator.dart';

/// Regulate selection highlight opacity here. Values 0.0–1.0.
/// Lower = more semi-transparent.
const double _selectionOpacity = 0.07;

class TrashScreen extends StatefulWidget {
  const TrashScreen({Key? key}) : super(key: key);

  @override
  TrashScreenState createState() => TrashScreenState();
}

class TrashScreenState extends State<TrashScreen> {
  static const Color _accent = Color(0xFFE09321);

  final _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  late final NotesApiService _notesApi;
  final ScrollController _scrollController = ScrollController();

  bool isLoading = true;
  bool isLoadingMore = false;
  String errorMessage = '';
  List<Message> trashMessages = [];
  bool _isFetchingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isSelectAllInProgress = false;
  int _selectAllProgressPage = 0;
  bool _selectAllCancelled = false;

  static const _selectAllRateLimitSeconds = 1;

  @override
  void initState() {
    super.initState();
    _notesApi = NotesApiService(_secureStorage);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 100 &&
          !_isFetchingMore &&
          _hasMore) {
        _loadMore();
      }
    });
    _fetchTrash(page: 1);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTrash({int page = 1, bool clearOld = false}) async {
    if (page == 1) {
      setState(() {
        if (clearOld) trashMessages.clear();
        isLoading = true;
        errorMessage = '';
        _hasMore = true;
      });
    }

    try {
      final newMessages = await _notesApi.fetchTrashPage(page: page);

      if (page == 1) {
        setState(() {
          trashMessages = newMessages;
        });
      } else {
        setState(() {
          trashMessages.addAll(newMessages);
        });
      }

      setState(() {
        isLoading = false;
      });

      if (newMessages.isEmpty) {
        setState(() {
          _hasMore = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = '$e';
        isLoading = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    _isFetchingMore = true;
    setState(() {
      isLoadingMore = true;
      _currentPage++;
    });
    await _fetchTrash(page: _currentPage);
    setState(() {
      isLoadingMore = false;
    });
    _isFetchingMore = false;
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
      Navigator.of(context)
          .push(MaterialPageRoute(
            builder: (_) => MessageDetailScreen(
              messageLink: msg.link,
              folder: 'sent',
            ),
          ))
          .then((result) {
        if (result == 'refresh' && mounted) {
          _currentPage = 1;
          _hasMore = true;
          _fetchTrash(page: 1, clearOld: false);
        }
      });
    }
  }

  Future<void> _selectAll() async {
    if (_isSelectAllInProgress) return;
    setState(() {
      _isSelectAllInProgress = true;
      _selectionMode = true;
      _selectedIds.clear();
      _selectAllProgressPage = 0;
      _selectAllCancelled = false;
    });

    int page = 1;
    while (mounted && !_selectAllCancelled) {
      setState(() => _selectAllProgressPage = page);
      List<Message> messages;
      try {
        messages = await _notesApi.fetchTrashPage(page: page);
      } catch (e) {
        if (mounted) {
          setState(() => _isSelectAllInProgress = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to fetch page $page: $e')),
          );
        }
        return;
      }

      if (messages.isEmpty) break;
      if (!mounted) return;
      setState(() {
        for (final m in messages) _selectedIds.add(m.id);
      });
      page++;
      await Future.delayed(const Duration(seconds: _selectAllRateLimitSeconds));
    }

    if (mounted) {
      setState(() => _isSelectAllInProgress = false);
    }
  }

  void _cancelSelectAll() {
    _selectAllCancelled = true;
  }

  Future<void> _restoreSelected() async {
    if (_selectedIds.isEmpty || _isSelectAllInProgress) return;
    final ids = _selectedIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Restore Notes', style: TextStyle(color: Colors.white)),
        content: Text(
          'Restore ${ids.length} note(s) from Trash?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Restore',
              style: TextStyle(color: _accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _notesApi.restoreNotesFromTrash(ids: ids);
      if (!mounted) return;
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      _currentPage = 1;
      _hasMore = true;
      await _fetchTrash(page: 1, clearOld: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restore: $e')),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty || _isSelectAllInProgress) return;
    final ids = _selectedIds.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Delete Permanently', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to permanently delete the selected notes? This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: _accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _notesApi.deleteNotesPermanently(ids: ids);
      if (!mounted) return;
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      _currentPage = 1;
      _hasMore = true;
      await _fetchTrash(page: 1, clearOld: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode && !_isSelectAllInProgress) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trash'),
          centerTitle: true,
          backgroundColor: Colors.black,
          actions: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectionMode)
                  InkResponse(
                    onTap: _isSelectAllInProgress ? null : _exitSelectionMode,
                    radius: 18,
                    child: Icon(
                      Icons.close,
                      color: _isSelectAllInProgress ? Colors.grey : Colors.white,
                    ),
                  ),
                if (_selectionMode) const SizedBox(width: 16),
                InkResponse(
                  onTap: (_selectedIds.isEmpty || _isSelectAllInProgress)
                      ? null
                      : _restoreSelected,
                  radius: 18,
                  child: Icon(
                    Icons.restore,
                    color: (_selectedIds.isEmpty || _isSelectAllInProgress)
                        ? Colors.grey
                        : Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                InkResponse(
                  onTap: (_selectedIds.isEmpty || _isSelectAllInProgress)
                      ? null
                      : _deleteSelected,
                  radius: 18,
                  child: Icon(
                    Icons.delete_forever,
                    color: (_selectedIds.isEmpty || _isSelectAllInProgress)
                        ? Colors.grey
                        : _accent,
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.black,
        body: Column(
          children: [
            if (_selectionMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.black,
                child: Row(
                  children: [
                    InkResponse(
                      onTap: _isSelectAllInProgress ? null : _selectAll,
                      radius: 18,
                      child: Text(
                        'Select All',
                        style: TextStyle(
                          color: _isSelectAllInProgress ? Colors.grey : _accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isSelectAllInProgress)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.grey[850],
                child: Row(
                  children: [
                    SizedBox(
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
              child: TrashMessageList(
          isLoading: isLoading,
          isLoadingMore: isLoadingMore,
          errorMessage: errorMessage,
          messages: trashMessages,
          scrollController: _scrollController,
          hasMore: _hasMore,
          onRefresh: () async {
            _currentPage = 1;
            _hasMore = true;
            await _fetchTrash(page: 1, clearOld: false);
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
    );
  }
}

/// Trash-specific list. Uses To/From, no preview, selection opacity from parent.
class TrashMessageList extends StatelessWidget {
  static const Color _accent = Color(0xFFE09321);

  final bool isLoading;
  final bool isLoadingMore;
  final String errorMessage;
  final List<Message> messages;
  final ScrollController scrollController;
  final bool hasMore;
  final Future<void> Function() onRefresh;
  final bool isSelectionMode;
  final Set<String> selectedIds;
  final void Function(Message msg) onLongPressItem;
  final void Function(Message msg) onTapItem;
  final double selectionOpacity;

  const TrashMessageList({
    Key? key,
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
    this.selectionOpacity = 0.18,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                size: 108.0,
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
          children: const [
            SizedBox(height: 180),
            Center(
              child: Text(
                'No messages in Trash.',
                style: TextStyle(color: Colors.white, fontSize: 16),
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
              padding: const EdgeInsets.symmetric(vertical: 44.0),
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

          final msg = messages[index];
          final isSelected = selectedIds.contains(msg.id);
          final otherParty = msg.recipient.isNotEmpty ? msg.recipient : msg.sender;
          return GestureDetector(
            onLongPress: () => onLongPressItem(msg),
            onTap: () => onTapItem(msg),
            child: Column(
              children: [
                Container(
                  color: isSelected
                      ? _accent.withOpacity(selectionOpacity)
                      : Colors.black,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8.0,
                    horizontal: 16.0,
                  ),
                  child: Row(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: isSelectionMode
                            ? _buildCheckbox(msg)
                            : const SizedBox.shrink(),
                      ),
                      if (msg.isUnread)
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
                              msg.subject,
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
                                  'Date: ${msg.date}',
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

  Widget _buildCheckbox(Message msg) {
    final isSelected = selectedIds.contains(msg.id);
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
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
