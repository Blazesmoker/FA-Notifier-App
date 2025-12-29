import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThumbnailDisplaySettingsProvider with ChangeNotifier {
  static const String _keyShowRatingOutline = 'thumb_show_rating_outline';
  static const String _keyShowTitleAuthor = 'thumb_show_title_author';

  bool _showRatingOutline = false;
  bool _showTitleAuthor = false;

  bool get showRatingOutline => _showRatingOutline;
  bool get showTitleAuthor => _showTitleAuthor;

  ThumbnailDisplaySettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _showRatingOutline = prefs.getBool(_keyShowRatingOutline) ?? false;
    _showTitleAuthor = prefs.getBool(_keyShowTitleAuthor) ?? false;
    notifyListeners();
  }

  Future<void> setShowRatingOutline(bool value) async {
    _showRatingOutline = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowRatingOutline, value);
  }

  Future<void> setShowTitleAuthor(bool value) async {
    _showTitleAuthor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowTitleAuthor, value);
  }
}


