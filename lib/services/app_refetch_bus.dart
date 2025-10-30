import 'dart:async';

class AppRefetchBus {
  static final _ctrl = StreamController<void>.broadcast();
  static Stream<void> get stream => _ctrl.stream;
  static void trigger() { if (!_ctrl.isClosed) _ctrl.add(null); }
  static void dispose() { _ctrl.close(); }
}
