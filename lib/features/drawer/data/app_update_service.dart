import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
  });

  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
}

Future<AppUpdateInfo?> fetchLatestAppUpdateInfo() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final current = info.version.trim();
    debugPrint('Current app version: $current');

    final uri = Uri.parse(
      'https://api.github.com/repos/Blazesmoker/FA-Notifier-App/releases/latest',
    );
    final resp = await http.get(
      uri,
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'FA-Notifier/UpdateCheck',
      },
    );
    debugPrint('GitHub API status: ${resp.statusCode}');

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String;
      final ghVer = tagName.startsWith('v') ? tagName.substring(1) : tagName;

      final updateInfo = AppUpdateInfo(
        currentVersion: current,
        latestVersion: ghVer,
        updateAvailable: ghVer != current,
      );

      debugPrint(
        'Remote version: $ghVer; show update = ${updateInfo.updateAvailable}',
      );
      return updateInfo;
    }

    debugPrint('Failed to fetch release: ${resp.body}');
    return null;
  } catch (e, st) {
    debugPrint('_checkForUpdate error: $e\n$st');
    return null;
  }
}
