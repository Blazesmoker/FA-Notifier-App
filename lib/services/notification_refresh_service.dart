import 'dart:async';

class NotificationRefreshService {
  static final NotificationRefreshService _instance = NotificationRefreshService._internal();

  factory NotificationRefreshService() {
    return _instance;
  }

  NotificationRefreshService._internal() {
  }

  final StreamController<void> _refreshController = StreamController<void>.broadcast();

  Stream<void> get onRefresh => _refreshController.stream;

  void triggerRefresh() => _refreshController.add(null);

  void dispose() => _refreshController.close();
}