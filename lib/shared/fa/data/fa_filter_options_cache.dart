import 'dart:async';

import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';

class FaFilterOptionsCache {
  final _changes = StreamController<FaFilterOptions>.broadcast(sync: true);
  final _pendingPages = <Future<void>>{};
  FaFilterOptions? _current;
  Future<FaFilterOptions>? _loading;
  int _generation = 0;
  int _requestSequence = 0;
  int _acceptedSequence = 0;
  bool _disposed = false;

  FaFilterOptions? get current => _current;
  Stream<FaFilterOptions> get changes => _changes.stream;

  Future<T> capture<T>(
    Future<T> Function(bool Function() isCancelled) request,
    FaFilterOptions? Function(T page) optionsOf, {
    bool Function()? isCancelled,
  }) {
    final generation = _generation;
    final sequence = ++_requestSequence;
    bool cancelled() =>
        _disposed ||
        generation != _generation ||
        (isCancelled?.call() ?? false);
    final result = Future<T>.sync(() => request(cancelled)).then((page) {
      if (!cancelled()) _accept(optionsOf(page), sequence);
      return page;
    });
    final pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _pendingPages.add(pending);
    unawaited(pending.then<void>((_) {
      _pendingPages.remove(pending);
    }));
    return result;
  }

  Future<FaFilterOptions> requireOptions({
    Future<FaFilterOptions?> Function(bool Function() isCancelled)? load,
  }) {
    final current = _current;
    if (current != null) return Future.value(current);
    final loading = _loading;
    if (loading != null) return loading;
    final future = _waitOrLoad(_generation, load);
    _loading = future;
    void completed() {
      if (identical(_loading, future)) _loading = null;
    }

    unawaited(future.then<void>(
      (_) => completed(),
      onError: (Object error, StackTrace stack) => completed(),
    ));
    return future;
  }

  Future<FaFilterOptions> _waitOrLoad(
    int generation,
    Future<FaFilterOptions?> Function(bool Function() isCancelled)? load,
  ) async {
    var waitedForPage = false;
    while (_pendingPages.isNotEmpty) {
      waitedForPage = true;
      await Future.wait(_pendingPages.toList());
      if (_disposed || generation != _generation) {
        throw StateError('Filter loading cancelled');
      }
      final current = _current;
      if (current != null) return current;
    }
    if (_disposed || generation != _generation) {
      throw StateError('Filter loading cancelled');
    }
    if (waitedForPage || load == null) {
      throw StateError('Filters were not available in the loaded page');
    }
    await capture<FaFilterOptions?>(load, (options) => options);
    if (_disposed || generation != _generation) {
      throw StateError('Filter loading cancelled');
    }
    final current = _current;
    if (current == null) {
      throw StateError('Filters were not available in the loaded page');
    }
    return current;
  }

  void _accept(FaFilterOptions? options, int sequence) {
    if (options == null || sequence < _acceptedSequence) return;
    _acceptedSequence = sequence;
    if (options == _current) return;
    _current = options;
    _changes.add(options);
  }

  void clear() {
    _generation++;
    _current = null;
    _loading = null;
    _pendingPages.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
    unawaited(_changes.close());
  }
}
