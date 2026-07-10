import 'dart:async';
import 'dart:collection';

class SimpleSemaphore {
  int _available;
  final Queue<Completer<void>> _waitQueue = Queue();

  SimpleSemaphore(this._available);

  Future<void> acquire() {
    if (_available > 0) {
      _available--;
      return Future.value();
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _available++;
    }
  }
}
