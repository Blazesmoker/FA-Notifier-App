import 'dart:async';

class NotesRefreshService {
  static final NotesRefreshService _i = NotesRefreshService._();
  factory NotesRefreshService() => _i;
  NotesRefreshService._();

  final _ctrl = StreamController<void>.broadcast();
  bool _hasPendingRefresh = false;
  Stream<void> get stream => _ctrl.stream;

  void triggerRefresh() {
    if (_ctrl.isClosed) return;
    if (!_ctrl.hasListener) {
      _hasPendingRefresh = true;
      return;
    }
    _ctrl.add(null);
  }

  bool takePendingRefresh() {
    final pending = _hasPendingRefresh;
    _hasPendingRefresh = false;
    return pending;
  }

  void dispose() => _ctrl.close();
}
