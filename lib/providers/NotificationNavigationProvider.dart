import 'package:flutter/foundation.dart';

class NotificationNavigationProvider with ChangeNotifier {
  int? _targetIndex;

  int? get targetIndex => _targetIndex;

  void setTargetIndex(int index) {
    _targetIndex = index;
    notifyListeners();
  }

  void reset() {
    _targetIndex = null;
    notifyListeners();
  }
}