import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:FANotifier/features/notes/data/notes_repository.dart';
import 'package:FANotifier/features/notes/domain/inbox_second_page_policy.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';
import 'package:FANotifier/features/notes/domain/notes_page_result.dart';
import 'package:FANotifier/features/notes/domain/notes_screen_view_state.dart';

typedef NotesScreenStateUpdater = void Function(VoidCallback update);

class NotesScreenController {
  NotesScreenController({
    required NotesRepository repository,
    required NotesScreenStateUpdater updateState,
  })  : _repository = repository,
        _updateState = updateState;

  final NotesRepository _repository;
  final NotesScreenStateUpdater _updateState;

  NotesScreenViewState _state = NotesScreenViewState.initial();
  NotesScreenViewState get state => _state;

  bool _isFetchingMoreInbox = false;
  int _currentInboxPage = 1;
  String? _lastInboxTopId;
  bool _isFetchingMoreSent = false;
  int _currentSentPage = 1;
  bool _hasLoadedSent = false;
  bool _sentNeedsRefresh = true;
  bool _didFirstRunSkip = false;
  NotesPageResult? _pendingFirstRunPage1;

  bool get isFetchingMoreInbox => _isFetchingMoreInbox;
  bool get isFetchingMoreSent => _isFetchingMoreSent;
  Stream<void> get refreshStream => _repository.refreshStream;

  bool takePendingRefresh() => _repository.takePendingRefresh();

  void setScreenVisible(bool visible) {
    _repository.setScreenVisible(visible);
  }

  void _setState(VoidCallback update) {
    _updateState(update);
  }

  Future<void> initialize() async {
    _didFirstRunSkip = await _repository.loadDidFirstRunSkip();
    if (!_didFirstRunSkip) {
      await _fetchTwoPagesAndSkip();
    }
  }

  Future<void> _fetchTwoPagesAndSkip() async {
    try {
      final combined = <Message>[];
      final page1 = await _repository.fetchPage(folder: 'inbox', page: 1);
      _pendingFirstRunPage1 = page1;
      combined.addAll(page1.messages);
      combined.addAll(
        await _repository.fetchMessages(folder: 'inbox', page: 2),
      );
      await _repository.markUnreadMessagesAsShown(combined);
      await _repository.markMessagesAsSeen(combined);
      await _repository.setFirstRunSkipDone();
      _didFirstRunSkip = true;
    } catch (_) {}
  }

  void resetInboxPagination() {
    _currentInboxPage = 1;
    _state = _state.copyWith(hasMoreInbox: true);
  }

  void resetSentPagination() {
    _currentSentPage = 1;
    _state = _state.copyWith(hasMoreSent: true);
  }

  void resetAllPagination() {
    resetInboxPagination();
    resetSentPagination();
  }

  void clearErrorsWithoutNotification() {
    _state = _state.copyWith(errorInbox: '', errorSent: '');
  }

  Future<void> refreshSentIfVisibleOrMarkStale({
    required bool sentVisible,
  }) async {
    resetSentPagination();
    _sentNeedsRefresh = true;
    if (sentVisible) {
      await ensureSentLoaded(force: true);
    }
  }

  Future<void> ensureSentLoaded({bool force = false}) async {
    if (_state.isLoadingSent) return;
    if (!force && _hasLoadedSent && !_sentNeedsRefresh) return;

    resetSentPagination();
    await fetchSent(page: 1, clearOld: false);

    if (_state.errorSent.isEmpty) {
      _hasLoadedSent = true;
      _sentNeedsRefresh = false;
    } else {
      _sentNeedsRefresh = true;
    }
  }

  void enterSelectionModeAndSelect(Message message) {
    _setState(() {
      _state = _state.copyWith(
        isSelectionMode: true,
        selectedIds: <String>{..._state.selectedIds, message.id},
      );
    });
  }

  void toggleSelection(Message message) {
    _setState(() {
      final selectedIds = <String>{..._state.selectedIds};
      var selectionMode = _state.isSelectionMode;
      if (selectedIds.contains(message.id)) {
        selectedIds.remove(message.id);
        if (selectedIds.isEmpty) selectionMode = false;
      } else {
        selectedIds.add(message.id);
      }
      _state = _state.copyWith(
        isSelectionMode: selectionMode,
        selectedIds: selectedIds,
      );
    });
  }

  void clearSelection() {
    _setState(() {
      _state = _state.copyWith(
        isSelectionMode: false,
        selectedIds: <String>{},
      );
    });
  }

  Future<void> moveNotesToTrash({
    required List<String> ids,
    required String folder,
  }) {
    return _repository.moveNotesToTrash(ids: ids, folder: folder);
  }

  Future<void> refreshAfterTrash(String folder) async {
    if (folder == 'inbox') {
      resetInboxPagination();
      await fetchInbox(
        page: 1,
        clearOld: false,
        suppressNewUnreadNotifications: true,
      );
      try {
        final page2 =
            await _repository.fetchMessages(folder: 'inbox', page: 2);
        await _repository.markUnreadMessagesAsShown(page2);
      } catch (e) {
        debugPrint('[_trashSelected] Failed to pre-mark page 2: $e');
      }
    } else {
      resetSentPagination();
      await fetchSent(page: 1, clearOld: false);
    }
  }

  Future<void> fetchInboxTwoPagesOnly() async {
    try {
      final shownIds = await _repository.getShownNoteIds();
      final seenIds = await _repository.getSeenNoteIds();
      final page1 = await _repository.fetchPage(folder: 'inbox', page: 1);
      final fetched = <Message>[...page1.messages];
      if (shouldFetchSecondInboxPage(
        page1Messages: page1.messages,
        shownNoteIds: shownIds,
        seenNoteIds: seenIds,
        topbarNotes: page1.topbarCounts?.notes,
      )) {
        fetched.addAll(
          await _repository.fetchMessages(folder: 'inbox', page: 2),
        );
      }
      await _handleNewUnreadMessages(fetched);
      await _repository.handleTopbarCounts(
        page1.topbarCounts,
        source: 'notes_screen_two_page_refresh',
      );
      await _repository.markMessagesAsSeen(fetched);
    } catch (e) {
      debugPrint('[Foreground fetchInboxTwoPagesOnly] error => $e');
    }
  }

  Future<void> fetchInbox({
    int page = 1,
    bool clearOld = false,
    bool suppressNewUnreadNotifications = false,
  }) async {
    if (page == 1) {
      _setState(() {
        _state = _state.copyWith(
          inboxMessages: clearOld ? <Message>[] : _state.inboxMessages,
          isLoadingInbox: true,
          errorInbox: '',
          hasMoreInbox: true,
        );
      });
    }

    try {
      final NotesPageResult result;
      if (page == 1 && _pendingFirstRunPage1 != null) {
        result = _pendingFirstRunPage1!;
        _pendingFirstRunPage1 = null;
      } else {
        result = await _repository.fetchPage(folder: 'inbox', page: page);
      }
      final newMessages = result.messages;

      if (page == 1) {
        _setState(() {
          _state = _state.copyWith(inboxMessages: newMessages);
        });
      } else {
        _setState(() {
          _state = _state.copyWith(
            inboxMessages: <Message>[
              ..._state.inboxMessages,
              ...newMessages,
            ],
          );
        });
      }

      _setState(() {
        _state = _state.copyWith(isLoadingInbox: false);
      });

      if (newMessages.isEmpty) {
        _setState(() {
          _state = _state.copyWith(hasMoreInbox: false);
        });
      }

      if (page == 1 && !suppressNewUnreadNotifications) {
        await _handleNewUnreadMessages(newMessages);
        await _repository.handleTopbarCounts(
          result.topbarCounts,
          source: 'notes_screen_inbox_refresh',
        );
      } else {
        await _repository.markUnreadMessagesAsShown(newMessages);
        if (page == 1 && newMessages.isNotEmpty) {
          _lastInboxTopId = newMessages.first.id;
        }
      }
      await _repository.markMessagesAsSeen(newMessages);
    } catch (e) {
      _setState(() {
        _state = _state.copyWith(
          errorInbox: '$e',
          isLoadingInbox: false,
          hasMoreInbox: false,
        );
      });
    }
  }

  Future<void> loadMoreInbox() async {
    _isFetchingMoreInbox = true;
    _setState(() {
      _state = _state.copyWith(isLoadingMoreInbox: true);
      _currentInboxPage++;
    });
    await fetchInbox(page: _currentInboxPage);
    _setState(() {
      _state = _state.copyWith(isLoadingMoreInbox: false);
    });
    _isFetchingMoreInbox = false;
  }

  Future<void> fetchSent({int page = 1, bool clearOld = false}) async {
    if (page == 1) {
      _setState(() {
        _state = _state.copyWith(
          sentMessages: clearOld ? <Message>[] : _state.sentMessages,
          isLoadingSent: true,
          errorSent: '',
          hasMoreSent: true,
        );
      });
    }

    try {
      final newMessages =
          await _repository.fetchMessages(folder: 'sent', page: page);

      if (page == 1) {
        _setState(() {
          _state = _state.copyWith(sentMessages: newMessages);
        });
      } else {
        _setState(() {
          _state = _state.copyWith(
            sentMessages: <Message>[
              ..._state.sentMessages,
              ...newMessages,
            ],
          );
        });
      }

      _setState(() {
        _state = _state.copyWith(isLoadingSent: false);
      });
      if (page == 1) {
        _hasLoadedSent = true;
        _sentNeedsRefresh = false;
      }

      if (newMessages.isEmpty) {
        _setState(() {
          _state = _state.copyWith(hasMoreSent: false);
        });
      }
    } catch (e) {
      _setState(() {
        _state = _state.copyWith(
          errorSent: '$e',
          isLoadingSent: false,
          hasMoreSent: false,
        );
      });
      if (page == 1) {
        _sentNeedsRefresh = true;
      }
    }
  }

  Future<void> loadMoreSent() async {
    _isFetchingMoreSent = true;
    _setState(() {
      _state = _state.copyWith(isLoadingMoreSent: true);
      _currentSentPage++;
    });
    await fetchSent(page: _currentSentPage);
    _setState(() {
      _state = _state.copyWith(isLoadingMoreSent: false);
    });
    _isFetchingMoreSent = false;
  }

  Future<int> _handleNewUnreadMessages(List<Message> fetchedInbox) async {
    final result = await _repository.handleNewUnreadMessages(
      fetchedInbox: fetchedInbox,
      previousTopId: _lastInboxTopId,
      didFirstRunSkip: _didFirstRunSkip,
    );
    _lastInboxTopId = result.latestTopId;
    return result.shownCount;
  }

  Future<void> markAsUnreadWithoutRefetch(Message message) {
    return _repository.markAsUnreadWithoutRefetch(message);
  }
}
