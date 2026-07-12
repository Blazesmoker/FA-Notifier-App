import 'package:flutter/foundation.dart';

class NotificationNavigationProvider extends ChangeNotifier {
  int? _targetIndex;

  int? get targetIndex => _targetIndex;
  bool get hasNavigationListeners => hasListeners;

  void setTargetIndex(int index) {
    _targetIndex = index;
    notifyListeners();
  }

  int? takeTargetIndex() {
    final value = _targetIndex;
    _targetIndex = null;
    return value;
  }

  void clear() {
    _targetIndex = null;
  }
}
