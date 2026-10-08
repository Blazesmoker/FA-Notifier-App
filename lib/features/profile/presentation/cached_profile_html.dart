import 'package:flutter/widgets.dart';

class CachedProfileHtml extends StatefulWidget {
  const CachedProfileHtml({
    super.key,
    required this.cacheKey,
    required this.child,
  }) : _childBuilder = null;

  const CachedProfileHtml.builder({
    super.key,
    required this.cacheKey,
    required Widget Function() builder,
  })  : child = const SizedBox.shrink(),
        _childBuilder = builder;

  final Object? cacheKey;
  final Widget child;
  final Widget Function()? _childBuilder;

  @override
  State<CachedProfileHtml> createState() => _CachedProfileHtmlState();
}

class _CachedProfileHtmlState extends State<CachedProfileHtml> {
  late Widget _child;

  Widget _createChild() => widget._childBuilder?.call() ?? widget.child;

  @override
  void initState() {
    super.initState();
    _child = _createChild();
  }

  @override
  void didUpdateWidget(covariant CachedProfileHtml oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _child = _createChild();
    }
  }

  @override
  Widget build(BuildContext context) => _child;
}
