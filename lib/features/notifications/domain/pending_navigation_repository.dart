abstract interface class PendingNavigationRepository {
  Future<String?> loadPayload({bool reload = false});

  Future<void> clearPayload();

  Future<void> savePayload(String payload);

  Future<void> recordHandledPayload(String payload);
}
