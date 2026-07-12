abstract interface class NsfwConfirmationRepository {
  Future<bool> loadDisabled();

  Future<void> saveDisabled(bool value);
}
