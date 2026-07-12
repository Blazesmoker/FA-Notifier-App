import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;

import 'package:FANotifier/core/fa/fa_media_auth.dart';

class FaNetworkImage extends StatefulWidget {
  const FaNetworkImage(
    this.src, {
    Key? key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.gaplessPlayback = false,
    this.filterQuality = FilterQuality.medium,
    this.isAntiAlias = false,
    this.color,
    this.opacity,
    this.colorBlendMode,
    this.frameBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.cacheWidth,
    this.cacheHeight,
  }) : super(key: key);

  final String src;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageRepeat repeat;
  final Rect? centerSlice;
  final bool matchTextDirection;
  final bool gaplessPlayback;
  final FilterQuality filterQuality;
  final bool isAntiAlias;
  final Color? color;
  final Animation<double>? opacity;
  final BlendMode? colorBlendMode;
  final ImageFrameBuilder? frameBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  State<FaNetworkImage> createState() => _FaNetworkImageState();
}

class _FaNetworkImageState extends State<FaNetworkImage> {
  late String _resolvedUrl;
  late bool _requiresHeaders;
  late Future<Map<String, String>?> _headersFuture;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(covariant FaNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) {
      _configure();
    }
  }

  void _configure() {
    _resolvedUrl = FaMediaAuth.normalizeUrl(widget.src);
    _requiresHeaders = FaMediaAuth.isFaUrl(_resolvedUrl);
    _headersFuture = FaMediaAuth.headersForUrl(_resolvedUrl);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>?>(
      future: _headersFuture,
      builder: (context, snapshot) {
        if (_requiresHeaders &&
            snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
          return SizedBox(width: widget.width, height: widget.height);
        }
        return Image.network(
          _resolvedUrl,
          headers: snapshot.data,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          repeat: widget.repeat,
          centerSlice: widget.centerSlice,
          matchTextDirection: widget.matchTextDirection,
          gaplessPlayback: widget.gaplessPlayback,
          filterQuality: widget.filterQuality,
          isAntiAlias: widget.isAntiAlias,
          color: widget.color,
          opacity: widget.opacity,
          colorBlendMode: widget.colorBlendMode,
          frameBuilder: widget.frameBuilder,
          loadingBuilder: widget.loadingBuilder,
          errorBuilder: widget.errorBuilder,
          semanticLabel: widget.semanticLabel,
          excludeFromSemantics: widget.excludeFromSemantics,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
        );
      },
    );
  }
}

Future<ImageProvider> faNetworkImageProvider(String url) async {
  final resolvedUrl = FaMediaAuth.normalizeUrl(url);
  final headers = await FaMediaAuth.headersForUrl(resolvedUrl);
  return NetworkImage(resolvedUrl, headers: headers);
}

html_pkg.HtmlExtension faHtmlImageExtension({
  double width = 50,
  double height = 50,
  BoxFit fit = BoxFit.contain,
}) {
  return html_pkg.TagExtension(
    tagsToExtend: {"img"},
    builder: (context) {
      final src = context.attributes['src'];
      if (src == null || src.trim().isEmpty) {
        return const SizedBox.shrink();
      }
      final trimmed = src.trim();
      if (!trimmed.startsWith('http') &&
          !trimmed.startsWith('//') &&
          !trimmed.startsWith('/')) {
        return const SizedBox.shrink();
      }
      return FaNetworkImage(
        trimmed,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      );
    },
  );
}
