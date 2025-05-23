import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class CacheMonitorService {
  static const int maxCacheSize = 100 * 1024 * 1024; // 100 MB
  final CacheManager _cacheManager;

  CacheMonitorService(this._cacheManager);
  InAppWebViewController? webViewController;

  Future<void> checkStorageUsage() async {
    final cacheDir = await getTemporaryDirectory();
    final dataDir = await getApplicationSupportDirectory(); // App's data directory

    final cacheSize = await _getDirectorySize(cacheDir);
    final dataSize = await _getDirectorySize(dataDir);

    print('Cache size: ${_formatBytes(cacheSize)}');
    print('Data size: ${_formatBytes(dataSize)}');

    if (cacheSize > maxCacheSize) {
      print('Cache exceeds limit. Clearing cache...');
      await _clearCacheDirectory(cacheDir);
      await InAppWebViewController.clearAllCache();

    }

    if (dataSize > maxCacheSize) {
      print('Data exceeds limit. Cleaning up app data...');
      await _clearDataDirectory(dataDir);
    }
  }

  Future<void> _clearCacheDirectory(Directory cacheDir) async {
    try {
      if (await cacheDir.exists()) {
        for (final file in cacheDir.listSync()) {
          await file.delete(recursive: true);
        }
        print('Cache directory cleared.');
      }
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  Future<void> _clearDataDirectory(Directory dataDir) async {
    try {
      if (await dataDir.exists()) {
        for (final file in dataDir.listSync()) {
          if (file is File && !_isProtectedFile(file)) {
            await file.delete();
          } else if (file is Directory && !_isProtectedDirectory(file)) {
            await file.delete(recursive: true);
          }
        }
        print('Data directory cleaned, except protected files.');
      }
    } catch (e) {
      print('Error clearing data: $e');
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
      print('Error calculating size: $e');
    }
    return size;
  }

  bool _isProtectedFile(File file) {
    final String path = file.path;
    return path.contains('shared_prefs') || path.contains('secure_storage');
  }

  bool _isProtectedDirectory(Directory dir) {
    final String path = dir.path;
    return path.contains('shared_prefs') || path.contains('secure_storage');
  }

  String _formatBytes(int bytes, [int decimals = 2]) {
    if (bytes <= 0) return '0 B';
    const List<String> suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final int i = (bytes.bitLength - 1) ~/ 10;
    final double size = bytes / (1 << (i * 10));
    return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
  }
}
