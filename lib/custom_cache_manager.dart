import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CustomCacheManager extends CacheManager {
  static const key = 'customCache';

  static final CustomCacheManager _instance = CustomCacheManager._internal();

  factory CustomCacheManager() {
    return _instance;
  }

  CustomCacheManager._internal()
      : super(
    Config(
      key,
      stalePeriod: const Duration(days: 4), // Cache validity
      maxNrOfCacheObjects: 200, // Maximum number of cached objects
    ),
  );
}
