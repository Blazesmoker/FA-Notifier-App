import 'package:flutter/widgets.dart';

enum ScrollReturnDirection { up, down }

typedef ScrollReturnAction = Future<void> Function(
  ValueChanged<ScrollReturnDirection> onStarted,
);

class ScrollReturnActionPort {
  ScrollReturnAction? _action;
  VoidCallback? _cancel;

  void bind(ScrollReturnAction action, VoidCallback cancel) {
    _action = action;
    _cancel = cancel;
  }

  void unbind(ScrollReturnAction action) {
    if (_action != action) return;
    _action = null;
    _cancel = null;
  }

  Future<void> invoke(ValueChanged<ScrollReturnDirection> onStarted) async {
    await _action?.call(onStarted);
  }

  void cancel() => _cancel?.call();
}

class ScrollReturnController {
  ScrollReturnController({
    required this.scrollController,
    this.onSavePosition,
    this.resolveReturnOffset,
  });

  static const double _tolerance = 2.0;
  static const Duration _duration = Duration(milliseconds: 260);

  final ScrollController scrollController;
  final VoidCallback? onSavePosition;
  final double Function(double savedOffset)? resolveReturnOffset;
  List<Object?> _content = [];
  double? _returnOffset;
  int _revision = 0;
  bool _busy = false;
  bool _dragInterrupted = false;
  bool _disposed = false;

  bool get isBusy => _busy;

  ScrollPosition? get _position {
    if (_disposed || !scrollController.hasClients ||
        scrollController.positions.length != 1) {
      return null;
    }
    final position = scrollController.position;
    return position.hasPixels && position.hasContentDimensions
        ? position
        : null;
  }

  void updateContent(Iterable<Object?> content) {
    final next = content.toList(growable: false);
    if (next.length < _content.length ||
        Iterable<int>.generate(_content.length).any(
          (index) => index >= next.length || _content[index] != next[index],
        )) {
      reset();
    }
    _content = next;
  }

  void handleScrollNotification(ScrollNotification notification) {
    if (!_busy || notification.metrics.axis != Axis.vertical) return;
    if ((notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        (notification is OverscrollNotification &&
            notification.dragDetails != null)) {
      _dragInterrupted = true;
    }
  }

  Future<void> perform({
    required ValueChanged<ScrollReturnDirection> onStarted,
    bool animate = true,
  }) async {
    final position = _position;
    if (_busy || _content.isEmpty || position == null) return;
    final atTop = position.pixels <= position.minScrollExtent + _tolerance;
    final direction = atTop
        ? ScrollReturnDirection.down
        : ScrollReturnDirection.up;
    if (atTop && _returnOffset == null) return;

    if (!atTop) {
      final saved = position.pixels
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (saved <= position.minScrollExtent + _tolerance) return;
      _returnOffset = saved;
      onSavePosition?.call();
    }
    final savedOffset = _returnOffset!;
    final revision = _revision;
    _busy = true;
    _dragInterrupted = false;
    try {
      onStarted(direction);
      if (!_valid(revision)) return;
      final target = direction == ScrollReturnDirection.up
          ? position.minScrollExtent
          : _resolve(savedOffset);
      if (animate) {
        await scrollController.animateTo(
          target, duration: _duration, curve: Curves.easeOutCubic,
        );
      } else {
        scrollController.jumpTo(target);
      }

      for (var correction = 0; correction < 3; correction++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!_valid(revision)) return;
        final current = _position!;
        final destination = direction == ScrollReturnDirection.up
            ? current.minScrollExtent
            : _resolve(savedOffset);
        if ((current.pixels - destination).abs() <= _tolerance) {
          if (direction == ScrollReturnDirection.down) _returnOffset = null;
          return;
        }
        final bounded = correction == 2
            ? destination.clamp(
                current.minScrollExtent, current.maxScrollExtent,
              ).toDouble()
            : destination;
        scrollController.jumpTo(bounded);
      }
      await WidgetsBinding.instance.endOfFrame;
      if (_valid(revision) && direction == ScrollReturnDirection.down &&
          (_position!.pixels - _resolve(savedOffset)).abs() <= _tolerance) {
        _returnOffset = null;
      }
    } finally {
      _busy = false;
    }
  }

  bool _valid(int revision) => !_disposed && !_dragInterrupted &&
      revision == _revision && _position != null;

  double _resolve(double savedOffset) {
    final resolved = resolveReturnOffset?.call(savedOffset) ?? savedOffset;
    final minimum = _position!.minScrollExtent;
    return resolved.isFinite && resolved >= minimum ? resolved : minimum;
  }

  void cancelMovement() {
    if (!_busy || _disposed) return;
    _revision++;
    final position = _position;
    if (position != null && !_dragInterrupted) {
      scrollController.jumpTo(position.pixels);
    }
  }

  void reset() {
    _returnOffset = null;
    final revision = ++_revision;
    if (!_busy) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !_busy || _dragInterrupted || revision != _revision) {
        return;
      }
      final position = _position;
      if (position != null) scrollController.jumpTo(position.pixels);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    _disposed = true;
    _revision++;
    _returnOffset = null;
    _content = [];
  }
}
