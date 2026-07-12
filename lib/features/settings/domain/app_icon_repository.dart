abstract interface class AppIconRepository {
  Future<bool> loadUseAdaptiveIcon();

  Future<void> setUseAdaptiveIcon(bool useAdaptiveIcon);
}
