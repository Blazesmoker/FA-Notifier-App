import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fanotifier/features/notes/domain/inbox_second_page_policy.dart';
import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/domain/note_activity_snapshot.dart';
import 'package:fanotifier/features/notes/domain/note_management.dart';
import 'package:fanotifier/features/notes/domain/notes_page_result.dart';
import 'package:fanotifier/features/notes/domain/notes_inbox_snapshot.dart';
import 'package:fanotifier/features/notes/domain/notes_repository.dart';
import 'package:fanotifier/features/notes/domain/notes_screen_view_state.dart';

typedef NotesScreenStateUpdater = void Function(VoidCallback update);

class NotesScreenController {
  NotesScreenController({
    required this._repository,
    required this._updateState,
  });

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
  int? _failedInboxPage;
  int? _failedSentPage;
  bool _sentSessionRecoveryPending = false;
  bool _didFirstRunSkip = false;
  NotesPageResult? _pendingFirstRunPage1;
  int? _pendingFirstRunPage1StartedAt;
  NoteActivitySnapshot? _pendingFirstRunActivity;
  Future<void>? _inFlightInboxPageOne;
  Future<void> _newUnreadHandlingQueue = Future<void>.value();
  NotesInboxSnapshot? _lastInboxSnapshot;

  bool get isFetchingMoreInbox => _isFetchingMoreInbox;
  bool get isFetchingMoreSent => _isFetchingMoreSent;
  bool get hasLoadedSent => _hasLoadedSent;
  Stream<void> get refreshStream => _repository.refreshStream;

  bool takePendingRefresh() => _repository.takePendingRefresh();

  void setScreenVisible(bool visible) {
    _repository.setScreenVisible(visible);
  }

  void bindInboxRefresh() {
    _repository.bindInboxRefresh(refreshInboxForPolling);
  }

  void unbindInboxRefresh() {
    _repository.unbindInboxRefresh(refreshInboxForPolling);
  }

  Future<NotesInboxSnapshot?> refreshInboxForPolling() async {
    _lastInboxSnapshot = null;
    _didFirstRunSkip = await _repository.loadDidFirstRunSkip();
    if (!_didFirstRunSkip) {
      final baseline = await _fetchTwoPagesAndSkip();
      if (baseline == null) {
        return null;
      }
      _pendingFirstRunPage1 = baseline.page;
      _pendingFirstRunPage1StartedAt = baseline.activity.startedAtMilliseconds;
      _pendingFirstRunActivity = baseline.activity;
    }
    await fetchInbox(
      checkSecondPage: true,
      reportActivities: false,
      preserveLoadedPages: true,
    );
    return _lastInboxSnapshot;
  }

  void _setState(VoidCallback update) {
    _updateState(update);
  }

  Future<void> initialize() async {
    _didFirstRunSkip = await _repository.loadDidFirstRunSkip();
    final cached = _repository.latestInboxSnapshot;
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch -
            (cached.activity.completedAtMilliseconds ??
                cached.activity.startedAtMilliseconds) < 240000) {
      _pendingFirstRunPage1 = cached.page;
      _pendingFirstRunPage1StartedAt = cached.activity.startedAtMilliseconds;
      _pendingFirstRunActivity = cached.activity;
      _didFirstRunSkip = await _repository.loadDidFirstRunSkip();
      return;
    }
    if (!_didFirstRunSkip) {
      final snapshot = await _repository.refreshInbox(_fetchTwoPagesAndSkip);
      _didFirstRunSkip = await _repository.loadDidFirstRunSkip();
      if (snapshot != null) {
        _pendingFirstRunPage1 = snapshot.page;
        _pendingFirstRunPage1StartedAt = snapshot.activity.startedAtMilliseconds;
        _pendingFirstRunActivity = snapshot.activity;
      }
    }
  }

  Future<NotesInboxSnapshot?> _fetchTwoPagesAndSkip() async {
    final generation = _repository.inboxGeneration;
    try {
      final combined = <Message>[];
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      final page1 = await _repository.fetchPage(folder: 'inbox', page: 1);
      if (page1.topbarCounts == null) {
        return null;
      }
      _pendingFirstRunPage1 = page1;
      _pendingFirstRunPage1StartedAt = startedAt;
      combined.addAll(page1.messages);
      combined.addAll(
        await _repository.fetchMessages(folder: 'inbox', page: 2),
      );
      if (generation != _repository.inboxGeneration) {
        return null;
      }
      await _repository.markUnreadMessagesAsShown(combined);
      await _repository.markMessagesAsSeen(combined);
      await _repository.setFirstRunSkipDone();
      _didFirstRunSkip = true;
      return NotesInboxSnapshot(
        page: page1,
        activity: NoteActivitySnapshot(
          messages: List<Message>.unmodifiable(combined),
          startedAtMilliseconds: page1.startedAtMilliseconds ?? startedAt,
          completedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
          unreadCount: page1.topbarCounts?.notes ?? 0,
          fetchedPage2: true,
        ),
      );
    } catch (_) {}
    return null;
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
    if (_sentSessionRecoveryPending && _failedSentPage != null) {
      _sentSessionRecoveryPending = false;
      await _recoverSentPage();
      return;
    }
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

  Future<void> recoverVerifiedSession({required bool sentVisible}) async {
    final inboxPage = _failedInboxPage;
    if (inboxPage != null && _state.errorInbox.isNotEmpty) {
      _setState(() {
        _state = _state.copyWith(errorInbox: '', hasMoreInbox: true);
      });
      await fetchInbox(page: inboxPage, clearOld: false);
    }
    if (_failedSentPage == null || _state.errorSent.isEmpty) return;
    if (sentVisible) {
      await _recoverSentPage();
    } else {
      _sentSessionRecoveryPending = true;
    }
  }

  Future<void> _recoverSentPage() async {
    final page = _failedSentPage;
    if (page == null) return;
    _setState(() {
      _state = _state.copyWith(errorSent: '', hasMoreSent: true);
    });
    await fetchSent(page: page, clearOld: false);
    if (_state.errorSent.isEmpty) {
      _hasLoadedSent = true;
      _sentNeedsRefresh = false;
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

  void toggleSelectAll(Iterable<Message> messages) {
    _setState(() {
      final loadedIds = messages.map((message) => message.id).toSet();
      final selectedIds = <String>{..._state.selectedIds};
      final allLoadedSelected = loadedIds.isNotEmpty &&
          loadedIds.every(selectedIds.contains);
      if (allLoadedSelected) {
        selectedIds.removeAll(loadedIds);
      } else {
        selectedIds.addAll(loadedIds);
      }
      _state = _state.copyWith(
        isSelectionMode: true,
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

  Future<void> applyManagementAction({
    required List<String> ids,
    required NotesFolder sourceFolder,
    required NoteManagementAction action,
  }) {
    return _repository.applyManagementAction(
      ids: ids,
      sourceFolder: sourceFolder,
      action: action,
    );
  }

  Future<void> refreshAfterManualUnread(List<String> ids) async {
    resetInboxPagination();
    await fetchInbox(
      page: 1,
      clearOld: false,
      manuallyMarkedUnreadIds: Set<String>.unmodifiable(ids),
    );
  }

  Future<void> refreshAfterManagementAction(NotesFolder folder) async {
    if (folder == NotesFolder.inbox) {
      await _inFlightInboxPageOne;
      resetInboxPagination();
      await fetchInbox(
        page: 1,
        clearOld: false,
      );
    } else {
      resetSentPagination();
      await fetchSent(page: 1, clearOld: false);
    }
  }

  Future<void> fetchInboxTwoPagesOnly() async {
    await _inFlightInboxPageOne;
    resetInboxPagination();
    await fetchInbox(checkSecondPage: true);
  }

  Future<void> fetchInbox({
    int page = 1,
    bool clearOld = false,
    bool suppressNewUnreadNotifications = false,
    Set<String> manuallyMarkedUnreadIds = const <String>{},
    bool checkSecondPage = true,
    bool reportActivities = true,
    bool preserveLoadedPages = false,
  }) {
    final shouldCoalesce = page == 1 &&
        !clearOld &&
        !suppressNewUnreadNotifications &&
        manuallyMarkedUnreadIds.isEmpty;
    final inFlight = _inFlightInboxPageOne;
    if (shouldCoalesce && inFlight != null) {
      return inFlight;
    }

    final operation = _fetchInbox(
      page: page,
      clearOld: clearOld,
      suppressNewUnreadNotifications: suppressNewUnreadNotifications,
      manuallyMarkedUnreadIds: manuallyMarkedUnreadIds,
      checkSecondPage: checkSecondPage,
      reportActivities: reportActivities,
      preserveLoadedPages: preserveLoadedPages,
    );
    if (!shouldCoalesce) return operation;

    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_inFlightInboxPageOne, tracked)) {
        _inFlightInboxPageOne = null;
      }
    });
    _inFlightInboxPageOne = tracked;
    return tracked;
  }

  Future<void> _fetchInbox({
    required int page,
    required bool clearOld,
    required bool suppressNewUnreadNotifications,
    required Set<String> manuallyMarkedUnreadIds,
    required bool checkSecondPage,
    required bool reportActivities,
    required bool preserveLoadedPages,
  }) async {
    final generation = _repository.inboxGeneration;
    var pageApplied = false;
    if (page == 1) {
      _setState(() {
        _state = _state.copyWith(
          inboxMessages: clearOld ? <Message>[] : _state.inboxMessages,
          isLoadingInbox: true,
          errorInbox: '',
          hasMoreInbox: preserveLoadedPages ? _state.hasMoreInbox : true,
        );
      });
    }

    try {
      final NotesPageResult result;
      final int snapshotStartedAt;
      NoteActivitySnapshot? cachedActivity;
      if (page == 1 &&
          _pendingFirstRunPage1 != null &&
          manuallyMarkedUnreadIds.isEmpty) {
        result = _pendingFirstRunPage1!;
        snapshotStartedAt = _pendingFirstRunPage1StartedAt!;
        _pendingFirstRunPage1 = null;
        _pendingFirstRunPage1StartedAt = null;
        cachedActivity = _pendingFirstRunActivity;
        _pendingFirstRunActivity = null;
      } else {
        if (page == 1 && manuallyMarkedUnreadIds.isNotEmpty) {
          _pendingFirstRunPage1 = null;
          _pendingFirstRunPage1StartedAt = null;
          _pendingFirstRunActivity = null;
        }
        result = await _repository.fetchPage(
          folder: 'inbox', page: page,
          requireFresh: manuallyMarkedUnreadIds.isNotEmpty,
        );
        snapshotStartedAt = result.startedAtMilliseconds ??
            DateTime.now().millisecondsSinceEpoch;
      }
      if (generation != _repository.inboxGeneration) {
        return;
      }
      final newMessages = result.messages;
      var activityMessages = page == 1 && result.topbarCounts != null
          ? newMessages
              .map((message) => Message(
                    id: message.id,
                    subject: message.subject,
                    sender: message.sender,
                    recipient: message.recipient,
                    date: message.date,
                    link: message.link,
                    isUnread: message.isUnread,
                  ))
              .toList(growable: false)
          : const <Message>[];

      if (page == 1 &&
          manuallyMarkedUnreadIds.isNotEmpty &&
          result.topbarCounts != null) {
        await _repository.reconcileManualUnread(
          noteIds: manuallyMarkedUnreadIds,
          snapshot: NoteActivitySnapshot(
            messages: activityMessages,
            startedAtMilliseconds: snapshotStartedAt,
            unreadCount: result.topbarCounts!.notes,
          ),
        );
      }

      if (page == 1) {
        _setState(() {
          final ids = newMessages.map((message) => message.id).toSet();
          _state = _state.copyWith(
            inboxMessages: preserveLoadedPages && _currentInboxPage > 1
                ? <Message>[
                    ...newMessages,
                    ..._state.inboxMessages.where((message) => ids.add(message.id)),
                  ]
                : newMessages,
          );
        });
      } else {
        _setState(() {
          final ids = _state.inboxMessages.map((message) => message.id).toSet();
          _state = _state.copyWith(
            inboxMessages: <Message>[
              ..._state.inboxMessages,
              ...newMessages.where((message) => ids.add(message.id)),
            ],
          );
        });
      }

      pageApplied = true;
      _failedInboxPage = null;
      _setState(() {
        _state = _state.copyWith(isLoadingInbox: false);
      });

      if (newMessages.isEmpty) {
        _setState(() {
          _state = _state.copyWith(hasMoreInbox: false);
        });
      }

      var observedMessages = cachedActivity?.messages ?? newMessages;
      var fetchedPage2 = cachedActivity?.fetchedPage2 ?? false;
      if (cachedActivity != null) {
        activityMessages = cachedActivity.messages;
      }
      if (page == 1 && !suppressNewUnreadNotifications) {
        if (checkSecondPage && !fetchedPage2) {
          final shownIds = await _repository.getShownNoteIds();
          final seenIds = await _repository.getSeenNoteIds();
          if (shouldFetchSecondInboxPage(
            page1Messages: newMessages,
            shownNoteIds: shownIds,
            seenNoteIds: seenIds,
            topbarNotes: result.topbarCounts?.notes,
          )) {
            try {
              final page2 = await _repository.fetchMessages(
                folder: 'inbox',
                page: 2,
              );
              observedMessages = <Message>[...newMessages, ...page2];
              activityMessages = <Message>[...activityMessages, ...page2];
              fetchedPage2 = true;
            } catch (_) {}
          }
        }
        if (generation != _repository.inboxGeneration) {
          return;
        }
        if (result.topbarCounts != null) {
          _lastInboxSnapshot = NotesInboxSnapshot(
            page: result,
            activity: NoteActivitySnapshot(
              messages: List<Message>.unmodifiable(activityMessages),
              startedAtMilliseconds: snapshotStartedAt,
              completedAtMilliseconds: cachedActivity?.completedAtMilliseconds ??
                  (fetchedPage2
                      ? DateTime.now().millisecondsSinceEpoch
                      : result.completedAtMilliseconds),
              unreadCount: result.topbarCounts!.notes,
              fetchedPage2: fetchedPage2,
            ),
          );
          _repository.rememberInboxSnapshot(_lastInboxSnapshot!);
        }
        if (!reportActivities) {
          unawaited(_finishInboxArrivals(observedMessages, generation));
          return;
        }
        await _handleNewUnreadMessages(observedMessages);
        if (reportActivities) {
          await _repository.handleTopbarCounts(
            result.topbarCounts,
            source: 'notes_screen_inbox_refresh',
            noteActivitySnapshot: _lastInboxSnapshot?.activity,
          );
        }
      } else {
        await _repository.markUnreadMessagesAsShown(newMessages);
        if (page == 1 && newMessages.isNotEmpty) {
          _lastInboxTopId = newMessages.first.id;
        }
      }
      await _repository.markMessagesAsSeen(observedMessages);
      if (page > 1) {
        await _repository.handleTopbarCounts(
          result.topbarCounts,
          source: 'notes_screen_inbox_page',
          startedAtMilliseconds: snapshotStartedAt,
        );
      }
    } catch (e) {
      if (!pageApplied) _failedInboxPage = page;
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

  Future<void> _finishInboxArrivals(List<Message> messages, int generation) async {
    try {
      await _handleNewUnreadMessages(messages);
      if (generation == _repository.inboxGeneration) {
        await _repository.markMessagesAsSeen(messages);
      }
    } catch (_) {}
  }

  Future<void> fetchSent({int page = 1, bool clearOld = false}) async {
    var pageApplied = false;
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

      pageApplied = true;
      _failedSentPage = null;
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
      if (!pageApplied) _failedSentPage = page;
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

  Future<int> _handleNewUnreadMessages(List<Message> fetchedInbox) {
    final operation = _newUnreadHandlingQueue.then((_) async {
      final result = await _repository.handleNewUnreadMessages(
        fetchedInbox: fetchedInbox,
        previousTopId: _lastInboxTopId,
        didFirstRunSkip: _didFirstRunSkip,
      );
      _lastInboxTopId = result.latestTopId;
      return result.shownCount;
    });
    _newUnreadHandlingQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> markAsUnreadWithoutRefetch(Message message) {
    return _repository.markAsUnreadWithoutRefetch(message);
  }
}
