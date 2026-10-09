import 'package:material_ui/material_ui.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;

import 'package:fanotifier/core/fa/fa_media_auth.dart';
import 'package:fanotifier/core/media/media_feature.dart';
import 'package:fanotifier/core/media/presentation/media_image_provider.dart';
import 'package:fanotifier/shared/widgets/fa_content_blur.dart';

class FaNetworkImage extends StatefulWidget {
  const FaNetworkImage(
    this.src, {
    super.key,
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
  });

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
  bool _loadFailed = false;
  bool _authRefreshScheduled = false;
  int _imageGeneration = 0;
  int _mediaRevision = 0;

  @override
  void initState() {
    super.initState();
    _configure();
    FaMediaAuth.changes.addListener(_handleAuthChanged);
  }

  @override
  void didUpdateWidget(covariant FaNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) {
      _configure();
    }
  }

  void _configure() {
    _loadFailed = false;
    _mediaRevision = FaMediaAuth.changes.value;
    _resolvedUrl = FaMediaAuth.normalizeUrl(widget.src);
    _requiresHeaders = FaMediaAuth.isFaUrl(_resolvedUrl);
    _headersFuture = FaMediaAuth.headersForUrl(_resolvedUrl);
  }

  void _handleAuthChanged() {
    if (!_requiresHeaders ||
        !_loadFailed ||
        _mediaRevision == FaMediaAuth.changes.value ||
        _authRefreshScheduled) {
      return;
    }
    _authRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authRefreshScheduled = false;
      if (!mounted ||
          !_requiresHeaders ||
          !_loadFailed ||
          _mediaRevision == FaMediaAuth.changes.value) {
        return;
      }
      setState(() {
        _imageGeneration++;
        _configure();
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    FaMediaAuth.changes.removeListener(_handleAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blurred = FaContentBlurScope.blurredOf(context);
    return FutureBuilder<Map<String, String>?>(
      key: ValueKey<int>(_imageGeneration),
      future: _headersFuture,
      builder: (context, snapshot) {
        if (_requiresHeaders &&
            snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
          return SizedBox(width: widget.width, height: widget.height);
        }
        return Image(
          image: ResizeImage.resizeIfNeeded(
            widget.cacheWidth,
            widget.cacheHeight,
            MediaImageProvider(
              url: _resolvedUrl,
              repository: MediaFeature.bytesRepository,
              sessionRevision: _mediaRevision,
              headers: snapshot.data,
            ),
          ),
          key: ValueKey<int>(_imageGeneration),
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
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null) {
              _loadFailed = false;
            }
            final image = blurred && !_loadFailed && frame != null
                ? FaImageBlur(blurred: true, child: child)
                : child;
            return widget.frameBuilder?.call(
                  context, image, frame, wasSynchronouslyLoaded,
                ) ??
                image;
          },
          loadingBuilder: widget.loadingBuilder,
          errorBuilder: (context, error, stackTrace) {
            _loadFailed = true;
            _handleAuthChanged();
            final builder = widget.errorBuilder;
            if (builder != null) return builder(context, error, stackTrace);
            return SizedBox(width: widget.width, height: widget.height);
          },
          semanticLabel: widget.semanticLabel,
          excludeFromSemantics: widget.excludeFromSemantics,
        );
      },
    );
  }
}

Future<ImageProvider> faNetworkImageProvider(String url) async {
  final resolvedUrl = FaMediaAuth.normalizeUrl(url);
  final headers = await FaMediaAuth.headersForUrl(resolvedUrl);
  return MediaImageProvider(
    url: resolvedUrl,
    repository: MediaFeature.bytesRepository,
    sessionRevision: FaMediaAuth.changes.value,
    headers: headers,
  );
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
