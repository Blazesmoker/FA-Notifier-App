import 'package:fanotifier/features/comments/data/comment_settings_preference.dart';
import 'package:flutter/foundation.dart';

class CommentSettingsProvider with ChangeNotifier {
  CommentSettingsProvider({
    this._preference = const CommentSettingsPreference(),
  }) {
    load();
  }

  final CommentSettingsPreference _preference;
  bool _collapsibleCommentsEnabled = true;

  bool get collapsibleCommentsEnabled => _collapsibleCommentsEnabled;

  Future<void> load() async {
    _collapsibleCommentsEnabled =
        await _preference.loadCollapsibleComments();
    notifyListeners();
  }

  Future<void> setCollapsibleComments(bool value) async {
    if (_collapsibleCommentsEnabled == value) return;
    _collapsibleCommentsEnabled = value;
    notifyListeners();
    await _preference.saveCollapsibleComments(value);
  }
}
