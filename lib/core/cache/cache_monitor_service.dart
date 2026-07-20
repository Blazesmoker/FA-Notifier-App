import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/cupertino.dart';

class CacheMonitorService {
  static const int maxCacheSize = 200 * 1024 * 1024;
  final CacheManager _cacheManager;

  CacheMonitorService(this._cacheManager);
  InAppWebViewController? webViewController;

  Future<void> checkStorageUsage() async {
    final cacheDir = await getTemporaryDirectory();
    final dataDir = await getApplicationSupportDirectory();

    final cacheSize = await _getDirectorySize(cacheDir);
    final dataSize = await _getDirectorySize(dataDir);

    debugPrint('Cache size: ${_formatBytes(cacheSize)}');
    debugPrint('Data size: ${_formatBytes(dataSize)}');

    if (cacheSize > maxCacheSize) {
      debugPrint('Cache exceeds limit. Using CacheManager to clean...');

      await _cacheManager.emptyCache();


      await InAppWebViewController.clearAllCache();

      debugPrint('Cache cleaned via CacheManager.');
    }

    if (dataSize > maxCacheSize) {
      debugPrint('Data exceeds limit. Cleaning up app data...');
      await _clearDataDirectory(dataDir);
    }
  }


  Future<void> _clearDataDirectory(Directory dataDir) async {
    try {
      if (await dataDir.exists()) {
        for (final file in dataDir.listSync()) {
          if (file is File && !_isProtectedFile(file)) {
            await file.delete();
          } else if (file is Directory && !_isProtectedDirectory(file)) {
            if (!file.path.contains('customCache') &&
                !file.path.contains('libCachedImageData')) {
              await file.delete(recursive: true);
            }
          }
        }
        debugPrint('Data directory cleaned, except protected files.');
      }
    } catch (e) {
      debugPrint('Error clearing data: $e');
    }
  }

  Future<int> _getDirectorySize(Directory directory) async {
    int size = 0;
    try {
      if (await directory.exists()) {
        for (final entity in directory.listSync(recursive: true)) {
          if (entity is File) {
            size += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('Error calculating size: $e');
    }
    return size;
  }

  bool _isProtectedFile(File file) {
    final String path = file.path;
    return path.contains('shared_prefs') ||
        path.contains('secure_storage') ||
        path.contains('customCache') ||
        path.contains('libCachedImageData');
  }

  bool _isProtectedDirectory(Directory dir) {
    final String path = dir.path;
    return path.contains('shared_prefs') ||
        path.contains('secure_storage') ||
        path.contains('customCache') ||
        path.contains('libCachedImageData');
  }

  String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return '0 B';
    const List<String> suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final int i = (bytes.bitLength - 1) ~/ 10;
    final double size = bytes / (1 << (i * 10));
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}