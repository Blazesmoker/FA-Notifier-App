import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.currentVersionAllowed,
  });

  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
  final bool currentVersionAllowed;
}

AppUpdateInfo? _cachedUpdateInfo;
Future<AppUpdateInfo?>? _inFlightUpdateInfoFuture;

Future<AppUpdateInfo?> fetchLatestAppUpdateInfo({bool forceRefresh = false}) {
  if (!forceRefresh && _cachedUpdateInfo != null) {
    return Future.value(_cachedUpdateInfo);
  }
  if (!forceRefresh && _inFlightUpdateInfoFuture != null) {
    return _inFlightUpdateInfoFuture!;
  }

  _inFlightUpdateInfoFuture = _fetchLatestAppUpdateInfoImpl().then((value) {
    _cachedUpdateInfo = value;
    _inFlightUpdateInfoFuture = null;
    return value;
  });
  return _inFlightUpdateInfoFuture!;
}

Future<AppUpdateInfo?> _fetchLatestAppUpdateInfoImpl() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final current = info.version.trim();
    debugPrint('Current app version: $current');

    final dio = _createGitHubDio();
    final responses = await Future.wait([
      dio.get<Map<String, dynamic>>('/releases/latest'),
      dio.get<Map<String, dynamic>>('/git/ref/tags/v$current'),
    ]);
    final latestResponse = responses[0];
    final currentTagResponse = responses[1];
    debugPrint('GitHub latest release API status: ${latestResponse.statusCode}');
    debugPrint('GitHub current tag API status: ${currentTagResponse.statusCode}');
    final currentVersionAllowed =
        _allowedFromTagStatus(currentTagResponse.statusCode);

    if (latestResponse.statusCode == 200 && latestResponse.data != null) {
      final tagName = latestResponse.data!['tag_name'] as String;
      final ghVer = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      final versionComparison = _compareVersions(current, ghVer);
      final currentIsNewer = versionComparison > 0;

      final updateInfo = AppUpdateInfo(
        currentVersion: current,
        latestVersion: ghVer,
        updateAvailable: versionComparison < 0,
        currentVersionAllowed:
            currentIsNewer || (currentVersionAllowed ?? true),
      );

      debugPrint(
        'Remote version: $ghVer; show update = ${updateInfo.updateAvailable}; '
        'current version allowed = ${updateInfo.currentVersionAllowed}',
      );
      return updateInfo;
    }

    if (currentVersionAllowed == false) {
      return AppUpdateInfo(
        currentVersion: current,
        latestVersion: current,
        updateAvailable: false,
        currentVersionAllowed: false,
      );
    }

    debugPrint('Failed to fetch latest GitHub release');
    return null;
  } catch (e, st) {
    debugPrint('_checkForUpdate error: $e\n$st');
    return null;
  }
}

Future<bool?> isCurrentAppVersionAllowed() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final current = info.version.trim();
    final dio = _createGitHubDio();
    final responses = await Future.wait([
      dio.get<Map<String, dynamic>>('/git/ref/tags/v$current'),
      dio.get<Map<String, dynamic>>('/releases/latest'),
    ]);
    final currentTagResponse = responses[0];
    final latestResponse = responses[1];
    debugPrint(
      'GitHub current tag API status: ${currentTagResponse.statusCode}; '
      'version: $current',
    );
    if (currentTagResponse.statusCode == 200) return true;

    if (latestResponse.statusCode == 200 && latestResponse.data != null) {
      final tagName = latestResponse.data!['tag_name'] as String;
      final latest = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (_compareVersions(current, latest) > 0) return true;
    }

    return _allowedFromTagStatus(currentTagResponse.statusCode);
  } catch (e, st) {
    debugPrint('isCurrentAppVersionAllowed error: $e\n$st');
    return null;
  }
}

Dio _createGitHubDio() {
  return Dio(
    BaseOptions(
      baseUrl: 'https://api.github.com/repos/Blazesmoker/FA-Notifier-App',
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'FA-Notifier/UpdateCheck',
        'X-GitHub-Api-Version': '2022-11-28',
      },
      validateStatus: (status) =>
          status != null && status >= 200 && status < 500,
    ),
  );
}

bool? _allowedFromTagStatus(int? statusCode) {
  return switch (statusCode) {
    200 => true,
    404 => false,
    _ => null,
  };
}

int _compareVersions(String first, String second) {
  final firstParts = first.split('.').map((part) => int.tryParse(part) ?? 0);
  final secondParts = second.split('.').map((part) => int.tryParse(part) ?? 0);
  final firstList = firstParts.toList();
  final secondList = secondParts.toList();
  final length =
      firstList.length > secondList.length ? firstList.length : secondList.length;

  for (var index = 0; index < length; index++) {
    final firstPart = index < firstList.length ? firstList[index] : 0;
    final secondPart = index < secondList.length ? secondList[index] : 0;
    if (firstPart != secondPart) return firstPart.compareTo(secondPart);
  }

  return 0;
}
