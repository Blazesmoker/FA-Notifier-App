import 'package:flutter/foundation.dart';

class NotificationNavigationProvider extends ChangeNotifier {
  int? _targetIndex;

  int? get targetIndex => _targetIndex;
  bool get hasNavigationListeners => hasListeners;

  /// Set a target tab, notifying listeners once.
  void setTargetIndex(int index) {
    _targetIndex = index;
    notifyListeners();
  }

  /// Consume the pending target without notifying again.
  int? takeTargetIndex() {
    final v = _targetIndex;
    _targetIndex = null;
    return v;
  }

  /// Optional: clear silently (no notify).
  void clear() {
    _targetIndex = null;
  }
}
