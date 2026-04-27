import 'dart:async';

class NotesRefreshService {
  static final NotesRefreshService _i = NotesRefreshService._();
  factory NotesRefreshService() => _i;
  NotesRefreshService._();

  final _ctrl = StreamController<void>.broadcast();
  Stream<void> get stream => _ctrl.stream;

  void triggerRefresh() {
    if (!_ctrl.isClosed) _ctrl.add(null);
  }

  void dispose() => _ctrl.close();
}
