import 'dart:async';

import 'package:fanotifier/features/notes/domain/notes_refresh_port.dart';

class NotesRefreshService implements NotesRefreshPort {
  static final NotesRefreshService _i = NotesRefreshService._();
  factory NotesRefreshService() => _i;
  NotesRefreshService._();

  final _ctrl = StreamController<void>.broadcast();
  bool _hasPendingRefresh = false;
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
