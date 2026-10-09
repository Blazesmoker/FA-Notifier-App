import 'dart:async';

import 'package:fanotifier/features/notes/domain/notes_refresh_port.dart';
import 'package:fanotifier/features/notes/domain/notes_inbox_snapshot.dart';
import 'package:fanotifier/features/notes/domain/notes_page_result.dart';
import 'package:fanotifier/features/notes/data/notes_unread_notification_service.dart';

class NotesRefreshService implements NotesRefreshPort {
  static final NotesRefreshService _i = NotesRefreshService._();
  factory NotesRefreshService() => _i;
  NotesRefreshService._();

  final _ctrl = StreamController<void>.broadcast();
  bool _hasPendingRefresh = false;
  final Map<int, Future<NotesPageResult>> _inFlightInboxPages = {};
  Future<NotesInboxSnapshot?>? _inFlightInboxRefresh;
  Future<NotesInboxSnapshot?> Function()? _inboxRefreshHandler;
  NotesInboxSnapshot? _latestInboxSnapshot;
  int _inboxGeneration = 0;

  @override
  NotesInboxSnapshot? get latestInboxSnapshot => _latestInboxSnapshot;

  @override
  int get inboxGeneration => _inboxGeneration;

  @override
  Future<NotesPageResult> fetchInboxPage(
    Future<NotesPageResult> Function() load, {
    int page = 1,
    bool requireFresh = false,
  }) async {
    final generation = _inboxGeneration;
    final existing = _inFlightInboxPages[page];
    if (existing != null) {
      if (!requireFresh) {
        return existing;
      }
      try {
        await existing;
      } catch (_) {}
    }
    if (generation != _inboxGeneration) {
      throw StateError('Notes session changed');
    }
    late final Future<NotesPageResult> request;
    request = load().whenComplete(() {
      if (identical(_inFlightInboxPages[page], request)) {
        _inFlightInboxPages.remove(page);
      }
    });
    _inFlightInboxPages[page] = request;
    return request;
  }

  @override
  Future<NotesInboxSnapshot?> refreshInbox(
    Future<NotesInboxSnapshot?> Function() fallback,
  ) {
    final existing = _inFlightInboxRefresh;
    if (existing != null) {
      return existing;
    }
    final generation = _inboxGeneration;
    late final Future<NotesInboxSnapshot?> request;
    request = (_inboxRefreshHandler ?? fallback)().then((snapshot) {
      if (generation != _inboxGeneration) {
        return null;
      }
      if (snapshot != null) {
        rememberInboxSnapshot(snapshot);
      }
      return snapshot;
    }).whenComplete(() {
      if (identical(_inFlightInboxRefresh, request)) {
        _inFlightInboxRefresh = null;
      }
    });
    _inFlightInboxRefresh = request;
    return request;
  }

  @override
  void bindInboxRefresh(Future<NotesInboxSnapshot?> Function() handler) {
    _inboxRefreshHandler = handler;
  }

  @override
  void unbindInboxRefresh(Future<NotesInboxSnapshot?> Function() handler) {
    if (_inboxRefreshHandler == handler) {
      _inboxRefreshHandler = null;
    }
  }

  @override
  void rememberInboxSnapshot(NotesInboxSnapshot snapshot) {
    if (snapshot.page.topbarCounts == null) {
      return;
    }
    if ((_latestInboxSnapshot?.activity.startedAtMilliseconds ?? 0) >
        snapshot.activity.startedAtMilliseconds) {
      return;
    }
    _latestInboxSnapshot = snapshot;
  }

  @override
  void clearInboxSnapshot() {
    NotesUnreadNotificationService.cancelPending();
    _inboxGeneration++;
    _latestInboxSnapshot = null;
    _inFlightInboxPages.clear();
    _inFlightInboxRefresh = null;
    _inboxRefreshHandler = null;
    _hasPendingRefresh = false;
  }
  @override
  Stream<void> get stream => _ctrl.stream;

  @override
  void triggerRefresh() {
    if (_ctrl.isClosed) return;
    if (!_ctrl.hasListener) {
      _hasPendingRefresh = true;
      return;
    }
    _ctrl.add(null);
  }

  @override
  bool takePendingRefresh() {
    final pending = _hasPendingRefresh;
    _hasPendingRefresh = false;
    return pending;
  }

  void dispose() => _ctrl.close();
}
