import 'dart:async';

abstract interface class NotificationRefreshPort {
  Stream<void> get onRefresh;

  void triggerRefresh();
}
