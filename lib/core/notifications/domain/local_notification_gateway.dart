abstract interface class LocalNotificationGateway {
  Future<void> showNotification(
    int id,
    String title,
    String body,
    String payload,
    String type, {
    int? badgeNumber,
  });
}
