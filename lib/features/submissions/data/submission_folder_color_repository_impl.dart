import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/submissions/domain/submission_folder_color_repository.dart';

class SubmissionFolderColorRepositoryImpl
    implements SubmissionFolderColorRepository {
  const SubmissionFolderColorRepositoryImpl();

  static const String _preferenceKey =
      'submission_management.folder_colors.v1';
  static const List<int> _palette = <int>[
    0xFF2E7D32,
    0xFFE09321,
    0xFF1565C0,
    0xFF7B1FA2,
    0xFF00897B,
    0xFFC2185B,
    0xFF5D4037,
    0xFF455A64,
  ];

  @override
  Future<Map<String, int>> colorsFor(Iterable<String> folderNames) async {
    final preferences = await SharedPreferences.getInstance();
    final storedColors = _decode(preferences.getString(_preferenceKey));
    var changed = false;
    for (final rawName in folderNames) {
      final name = rawName.trim();
      if (name.isEmpty || storedColors.containsKey(name)) continue;
      storedColors[name] = _palette[storedColors.length % _palette.length];
      changed = true;
    }
    if (changed) {
      await preferences.setString(_preferenceKey, jsonEncode(storedColors));
    }
    return Map<String, int>.unmodifiable(storedColors);
  }

  @override
  Future<void> setColor(String folderName, int colorValue) async {
    final name = folderName.trim();
    if (name.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    final storedColors = _decode(preferences.getString(_preferenceKey));
    storedColors[name] = colorValue;
    await preferences.setString(_preferenceKey, jsonEncode(storedColors));
  }

  Map<String, int> _decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return <String, int>{};
    try {
      final value = jsonDecode(encoded);
      if (value is! Map) return <String, int>{};
      final colors = <String, int>{};
      for (final entry in value.entries) {
        final name = entry.key;
        final color = entry.value;
        if (name is String && color is int) colors[name] = color;
      }
      return colors;
    } on FormatException {
      return <String, int>{};
    }
  }
}
