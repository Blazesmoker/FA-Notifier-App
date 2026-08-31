import 'package:flutter/widgets.dart';

class CachedProfileHtml extends StatefulWidget {
  const CachedProfileHtml({
    super.key,
    required this.cacheKey,
    required this.child,
  });

  final Object? cacheKey;
  final Widget child;

  @override
  State<CachedProfileHtml> createState() => _CachedProfileHtmlState();
}

class _CachedProfileHtmlState extends State<CachedProfileHtml> {
  late Widget _child;

  @override
  void initState() {
    super.initState();
    _child = widget.child;
  }

  @override
  void didUpdateWidget(covariant CachedProfileHtml oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _child = widget.child;
    }
  }

  @override
  Widget build(BuildContext context) => _child;
}
