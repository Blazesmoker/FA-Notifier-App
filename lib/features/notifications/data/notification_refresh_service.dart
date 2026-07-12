import 'dart:async';

import 'package:FANotifier/features/notifications/domain/notification_refresh_port.dart';

class NotificationRefreshService implements NotificationRefreshPort {
  static final NotificationRefreshService _instance = NotificationRefreshService._internal();

  factory NotificationRefreshService() {
    return _instance;
  }

  NotificationRefreshService._internal() {
  }

  final StreamController<void> _refreshController = StreamController<void>.broadcast();

  @override
  Stream<void> get onRefresh => _refreshController.stream;

  @override
  void triggerRefresh() => _refreshController.add(null);

  void dispose() => _refreshController.close();
}
