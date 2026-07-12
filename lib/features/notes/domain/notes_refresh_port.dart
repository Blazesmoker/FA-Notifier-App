import 'dart:async';

abstract interface class NotesRefreshPort {
  Stream<void> get stream;

  void triggerRefresh();

  bool takePendingRefresh();
}
