import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/comment_tree_painter.dart';

typedef ThreadedCommentItemBuilder = Widget Function(
  BuildContext context,
  ThreadedCommentItem item,
);

class ThreadedCommentItem {
  const ThreadedCommentItem({
    required this.comment,
    required this.index,
    required this.treeLevels,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.animationDuration,
    required this.animationCurve,
  });

  final Map<String, dynamic> comment;
  final int index;
  final ValueListenable<CommentTreeLevels> treeLevels;
  final ValueListenable<bool> collapsed;
  final VoidCallback? onToggleCollapse;
  final Duration animationDuration;
  final Curve animationCurve;
}

class SliverThreadedComments extends StatefulWidget {
  const SliverThreadedComments({
    super.key,
    required this.comments,
    required this.itemBuilder,
    this.collapsible = true,
    this.animationDuration = const Duration(milliseconds: 250),
    this.animationCurve = Curves.easeInOut,
  });

  final List<Map<String, dynamic>> comments;
  final ThreadedCommentItemBuilder itemBuilder;
  final bool collapsible;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  State<SliverThreadedComments> createState() =>
      _SliverThreadedCommentsState();
}

class _SliverThreadedCommentsState extends State<SliverThreadedComments> {
  late final _ThreadedCommentsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _ThreadedCommentsController()..sync(widget.comments);
  }

  @override
  void didUpdateWidget(covariant SliverThreadedComments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.comments, widget.comments)) {
      _controller.sync(widget.comments);
    }
    if (oldWidget.collapsible != widget.collapsible &&
        !widget.collapsible) {
      _controller.expandAll();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final node = _controller.nodeAt(index);
          final item = ThreadedCommentItem(
            comment: node.comment,
            index: index,
            treeLevels: node.treeLevels,
            collapsed: node.collapsed,
            onToggleCollapse:
                widget.collapsible ? () => _controller.toggle(index) : null,
            animationDuration: widget.animationDuration,
            animationCurve: widget.animationCurve,
          );

          return _ThreadedCommentVisibility(
            key: ValueKey<String>('threaded-comment-${node.key}'),
            isVisible: node.isVisible,
            duration: widget.animationDuration,
            curve: widget.animationCurve,
            child: widget.itemBuilder(context, item),
          );
        },
        childCount: _controller.length,
      ),
    );
  }
}

class _ThreadedCommentVisibility extends StatefulWidget {
  const _ThreadedCommentVisibility({
    super.key,
    required this.isVisible,
    required this.duration,
    required this.curve,
    required this.child,
  });

  final ValueListenable<bool> isVisible;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<_ThreadedCommentVisibility> createState() =>
      _ThreadedCommentVisibilityState();
}

class _ThreadedCommentVisibilityState
    extends State<_ThreadedCommentVisibility>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late Animation<double> _sizeFactor;
  late bool _isVisible;
  late bool _includeChild;

  @override
  void initState() {
    super.initState();
    _isVisible = widget.isVisible.value;
    _includeChild = _isVisible;
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: _isVisible ? 1 : 0,
    )..addStatusListener(_handleAnimationStatus);
    _sizeFactor = CurvedAnimation(
      parent: _animationController,
      curve: widget.curve,
    );
    widget.isVisible.addListener(_handleVisibilityChanged);
  }

  @override
  void didUpdateWidget(covariant _ThreadedCommentVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    final visibilityChanged = oldWidget.isVisible != widget.isVisible;
    if (visibilityChanged) {
      oldWidget.isVisible.removeListener(_handleVisibilityChanged);
      widget.isVisible.addListener(_handleVisibilityChanged);
    }
    _animationController.duration = widget.duration;
    if (oldWidget.curve != widget.curve) {
      _sizeFactor = CurvedAnimation(
        parent: _animationController,
        curve: widget.curve,
      );
    }
    if (visibilityChanged) {
      _syncWithoutAnimation();
    } else {
      _handleVisibilityChanged();
    }
  }

  void _syncWithoutAnimation() {
    _isVisible = widget.isVisible.value;
    _includeChild = _isVisible;
    _animationController.value = _isVisible ? 1 : 0;
  }

  void _handleVisibilityChanged() {
    final shouldBeVisible = widget.isVisible.value;
    if (shouldBeVisible == _isVisible) return;

    _isVisible = shouldBeVisible;
    if (shouldBeVisible) {
      if (!_includeChild) {
        setState(() {
          _includeChild = true;
        });
      }
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed ||
        _isVisible ||
        !_includeChild ||
        !mounted) {
      return;
    }
    setState(() {
      _includeChild = false;
    });
  }

  @override
  void dispose() {
    widget.isVisible.removeListener(_handleVisibilityChanged);
    _animationController
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_includeChild) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _sizeFactor,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        return ClipRect(
          clipper: const _CommentVisibilityClipper(topOverflow: 6),
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _sizeFactor.value,
            child: child,
          ),
        );
      },
    );
  }
}

class _CommentVisibilityClipper extends CustomClipper<Rect> {
  const _CommentVisibilityClipper({required this.topOverflow});

  final double topOverflow;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, -topOverflow, size.width, size.height);
  }

  @override
  bool shouldReclip(covariant _CommentVisibilityClipper oldClipper) {
    return oldClipper.topOverflow != topOverflow;
  }
}

class _ThreadedCommentsController {
  List<_ThreadedCommentNode> _nodes = const [];
  final Map<String, _ThreadedCommentNode> _nodesByKey =
      <String, _ThreadedCommentNode>{};
  final Set<_ThreadedCommentNode> _retiredNodes =
      <_ThreadedCommentNode>{};

  int get length => _nodes.length;

  _ThreadedCommentNode nodeAt(int index) => _nodes[index];

  void sync(List<Map<String, dynamic>> comments) {
    final keysByBase = <String, int>{};
    final activeKeys = <String>{};
    final levels = comments.map(_nestingLevel).toList(growable: false);
    final nodes = <_ThreadedCommentNode>[];
    final ancestorIndexes = <int>[];

    for (var index = 0; index < comments.length; index++) {
      final level = levels[index];
      while (ancestorIndexes.isNotEmpty &&
          levels[ancestorIndexes.last] >= level) {
        ancestorIndexes.removeLast();
      }

      final comment = comments[index];
      final rawId = comment['commentId']?.toString().trim() ?? '';
      final baseKey = rawId.isNotEmpty
          ? 'id:$rawId'
          : 'item:${identityHashCode(comment)}';
      final occurrence = keysByBase.update(
        baseKey,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final key = '$baseKey:$occurrence';
      activeKeys.add(key);
      final ancestorKeys = ancestorIndexes
          .map((ancestorIndex) => nodes[ancestorIndex].key)
          .toList(growable: false);

      var descendantCount = 0;
      for (var nextIndex = index + 1;
          nextIndex < comments.length && levels[nextIndex] > level;
          nextIndex++) {
        descendantCount++;
      }

      final node = _nodesByKey.putIfAbsent(
        key,
        () => _ThreadedCommentNode(key: key),
      );
      node
        ..comment = comment
        ..nestingLevel = level
        ..ancestorKeys = ancestorKeys
        ..descendantCount = descendantCount;
      nodes.add(node);
      ancestorIndexes.add(index);
    }

    _nodes = nodes;
    final staleKeys = _nodesByKey.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in staleKeys) {
      final retired = _nodesByKey.remove(key);
      if (retired != null) {
        _retiredNodes.add(retired);
      }
    }
    if (_retiredNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in _retiredNodes.toList(growable: false)) {
          if (_retiredNodes.remove(node)) {
            node.dispose();
          }
        }
      });
    }
    _refreshVisibility();
  }

  void toggle(int index) {
    final node = _nodes[index];
    node.collapsed.value = !node.collapsed.value;
    if (node.descendantCount > 0) {
      final end = index + node.descendantCount + 1;
      for (var descendantIndex = index + 1;
          descendantIndex < end;
          descendantIndex++) {
        _refreshNodeVisibility(_nodes[descendantIndex]);
      }
    }
    _refreshTreeLevels();
  }

  void expandAll() {
    var changed = false;
    for (final node in _nodes) {
      if (node.collapsed.value) {
        node.collapsed.value = false;
        changed = true;
      }
    }
    if (changed) {
      _refreshVisibility();
    }
  }

  void _refreshVisibility() {
    for (final node in _nodes) {
      _refreshNodeVisibility(node);
    }
    _refreshTreeLevels();
  }

  void _refreshNodeVisibility(_ThreadedCommentNode node) {
    final isVisible = !node.ancestorKeys.any(
      (key) => _nodesByKey[key]?.collapsed.value ?? false,
    );
    if (node.isVisible.value != isVisible) {
      node.isVisible.value = isVisible;
    }
  }

  void _refreshTreeLevels() {
    final visibleNodes = _nodes
        .where((node) => node.isVisible.value)
        .toList(growable: false);
    for (var index = 0; index < visibleNodes.length; index++) {
      final node = visibleNodes[index];
      final previous = index == 0 ? 0 : visibleNodes[index - 1].nestingLevel;
      final next = index + 1 == visibleNodes.length
          ? 0
          : visibleNodes[index + 1].nestingLevel;
      final current = node.treeLevels.value;
      if (current.previous != previous || current.next != next) {
        node.treeLevels.value = CommentTreeLevels(
          previous: previous,
          next: next,
        );
      }
    }
  }

  static int _nestingLevel(Map<String, dynamic> comment) {
    final width = (comment['width'] as num?)?.toDouble() ?? 100;
    return ((100 - width) / 3).round().clamp(0, 4).toInt();
  }

  void dispose() {
    for (final node in _nodesByKey.values) {
      node.dispose();
    }
    for (final node in _retiredNodes) {
      node.dispose();
    }
    _retiredNodes.clear();
  }
}

class _ThreadedCommentNode {
  _ThreadedCommentNode({required this.key});

  final String key;
  Map<String, dynamic> comment = const <String, dynamic>{};
  int nestingLevel = 0;
  List<String> ancestorKeys = const <String>[];
  int descendantCount = 0;
  final ValueNotifier<bool> collapsed = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isVisible = ValueNotifier<bool>(true);
  final ValueNotifier<CommentTreeLevels> treeLevels =
      ValueNotifier<CommentTreeLevels>(
    const CommentTreeLevels(previous: 0, next: 0),
  );

  void dispose() {
    collapsed.dispose();
    isVisible.dispose();
    treeLevels.dispose();
  }
}
