import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:fanotifier/features/submissions/domain/openpost_file_download_result.dart';
import 'package:fanotifier/features/submissions/domain/openpost_submission_attachment.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';

const Color _attachmentSurfaceColor = Color(0xFF151515);

class OpenPostSubmissionContent extends StatefulWidget {
  const OpenPostSubmissionContent({
    required this.attachment,
    required this.onDownload,
    required this.onShowMessage,
    required this.routeDetached,
    this.selectionAreaKey,
    this.onSelectionChanged,
    this.contextMenuBuilder,
    super.key,
  });

  final OpenPostSubmissionAttachment attachment;
  final Future<OpenPostFileDownloadResult> Function() onDownload;
  final void Function(String message, Color backgroundColor) onShowMessage;
  final bool routeDetached;
  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final Widget Function(BuildContext, SelectableRegionState)?
      contextMenuBuilder;

  @override
  State<OpenPostSubmissionContent> createState() =>
      _OpenPostSubmissionContentState();
}

class _OpenPostSubmissionContentState
    extends State<OpenPostSubmissionContent> {
  bool _isDownloading = false;
  bool _showFullFileName = false;

  @override
  void didUpdateWidget(covariant OpenPostSubmissionContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.fileName != widget.attachment.fileName) {
      _showFullFileName = false;
    }
  }

  Future<void> _download() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
    });
    final result = await widget.onDownload();
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
    });
    _showDownloadResult(result);
  }

  void _showDownloadResult(OpenPostFileDownloadResult result) {
    switch (result.status) {
      case OpenPostFileDownloadStatus.saved:
        _showMessage('File saved.', Colors.green);
        return;
      case OpenPostFileDownloadStatus.cancelled:
        return;
      case OpenPostFileDownloadStatus.httpFailure:
        final statusCode = result.statusCode;
        _showMessage(
          statusCode == null
              ? 'Failed to download file.'
              : 'Failed to download file. HTTP $statusCode.',
          Colors.red,
        );
        return;
      case OpenPostFileDownloadStatus.failed:
        _showMessage('Failed to download file.', Colors.red);
        return;
    }
  }

  void _showMessage(String message, Color backgroundColor) {
    widget.onShowMessage(message, backgroundColor);
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final isMusic =
        attachment.kind == OpenPostSubmissionAttachmentKind.music;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _attachmentSurfaceColor,
          border: Border.all(color: const Color(0xFF2A2A2A)),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    isMusic ? Icons.audiotrack : Icons.description_outlined,
                    color: const Color(0xFFE09321),
                    size: 27.0,
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: _showFullFileName
                              ? 'Use compact file name'
                              : 'Show full file name',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4.0),
                            onTap: () {
                              setState(() {
                                _showFullFileName = !_showFullFileName;
                              });
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 1.0),
                              child: Text(
                                attachment.fileName,
                                maxLines: _showFullFileName ? null : 2,
                                overflow: _showFullFileName
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize:
                                      _showFullFileName ? 11.0 : 15.0,
                                  height: _showFullFileName ? 1.2 : null,
                                  fontWeight: _showFullFileName
                                      ? FontWeight.w500
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          isMusic
                              ? 'Music · ${attachment.extension.toUpperCase()}'
                              : 'Document · ${attachment.extension.toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Tooltip(
                    message: 'Download',
                    child: SizedBox.square(
                      dimension: 44.0,
                      child: OutlinedButton(
                        onPressed: _isDownloading ? null : _download,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE09321),
                          side: const BorderSide(color: Color(0xFF5A4A32)),
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                        ),
                        child: _isDownloading
                            ? const SizedBox(
                                width: 17.0,
                                height: 17.0,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                ),
                              )
                            : const Icon(
                                Icons.download_outlined,
                                size: 20.0,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),
              _buildContent(attachment),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(OpenPostSubmissionAttachment attachment) {
    if (attachment.supportsPlayback) {
      return _OpenPostAudioPlayer(
        url: attachment.playbackUrl!,
        routeDetached: widget.routeDetached,
      );
    }
    if (attachment.kind == OpenPostSubmissionAttachmentKind.music) {
      return const _AttachmentFallback(
        icon: Icons.music_off_outlined,
        message:
            'MIDI playback is not available. Download the original file to open it.',
      );
    }
    if (attachment.supportsPreview) {
      return _OpenPostDocumentViewer(
        attachment: attachment,
        routeDetached: widget.routeDetached,
        selectionAreaKey: widget.selectionAreaKey,
        onSelectionChanged: widget.onSelectionChanged,
        contextMenuBuilder: widget.contextMenuBuilder,
      );
    }
    return const _AttachmentFallback(
      icon: Icons.file_download_outlined,
      message:
          'Preview is not available for legacy DOC files. Download the original file to open it.',
    );
  }
}

class _AttachmentFallback extends StatelessWidget {
  const _AttachmentFallback({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      decoration: BoxDecoration(
        color: _attachmentSurfaceColor,
        borderRadius: BorderRadius.circular(7.0),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 24.0),
          const SizedBox(width: 12.0),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13.0,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenPostAudioPlayer extends StatelessWidget {
  const _OpenPostAudioPlayer({
    required this.url,
    required this.routeDetached,
  });

  static const double _height = 112.0;

  final String url;
  final bool routeDetached;

  @override
  Widget build(BuildContext context) {
    if (routeDetached) {
      return const ColoredBox(
        color: _attachmentSurfaceColor,
        child: SizedBox(
          width: double.infinity,
          height: _height,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(7.0),
      child: ColoredBox(
        color: _attachmentSurfaceColor,
        child: SizedBox(
          width: double.infinity,
          height: _height,
          child: InAppWebView(
            key: ValueKey<String>(url),
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => HorizontalDragGestureRecognizer(),
              ),
            },
            initialData: InAppWebViewInitialData(
              data: _audioHtml(url),
              baseUrl: WebUri('https://www.furaffinity.net'),
              encoding: 'utf-8',
              mimeType: 'text/html',
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: true,
              allowsInlineMediaPlayback: true,
              disableVerticalScroll: false,
              disableHorizontalScroll: false,
              verticalScrollBarEnabled: false,
              horizontalScrollBarEnabled: false,
              supportZoom: false,
              useHybridComposition: false,
              transparentBackground: true,
            ),
          ),
        ),
      ),
    );
  }

  static String _audioHtml(String url) {
    final encodedUrl = jsonEncode(url);
    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{box-sizing:border-box}
html,body{width:100%;height:100%;margin:0;overflow:hidden;background:#151515;color:#fff;color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
.player{position:relative;height:100%;padding:8px 12px 4px}
audio{display:block;width:100%;height:54px;touch-action:pan-x}
.rate{display:grid;grid-template-columns:auto minmax(80px,1fr) 42px;gap:10px;align-items:center;height:42px;font-size:13px;color:#bbb}
input{width:100%;accent-color:#e09321;touch-action:pan-x}
output{text-align:right;color:#e09321;font-variant-numeric:tabular-nums}
#error{display:none;position:absolute;left:12px;right:12px;bottom:1px;padding:1px 3px;background:rgba(21,21,21,.92);font-size:10px;color:#ff7777}
#error:not(:empty){display:block}
</style>
</head>
<body>
<div class="player">
<audio id="player" controls controlslist="nodownload noplaybackrate" preload="metadata"></audio>
<div class="rate">
<label for="rate">Speed</label>
<input id="rate" type="range" min="0.25" max="2" step="0.25" value="1">
<output id="rateValue">1×</output>
</div>
<div id="error"></div>
</div>
<script>
const player=document.getElementById('player');
const rate=document.getElementById('rate');
const rateValue=document.getElementById('rateValue');
player.src=$encodedUrl;
function applyRate(){
  const value=Number(rate.value);
  player.defaultPlaybackRate=value;
  player.playbackRate=value;
  const label=Number.isInteger(value)?value.toFixed(0):value.toFixed(2).replace(/0\$/,'');
  rateValue.textContent=label+'×';
}
rate.addEventListener('input',applyRate);
player.addEventListener('loadedmetadata',applyRate);
player.addEventListener('error',function(){
  document.getElementById('error').textContent='Unable to play this file. You can still download it.';
});
applyRate();
</script>
</body>
</html>
''';
  }
}

class _OpenPostDocumentInspectScreen extends StatelessWidget {
  const _OpenPostDocumentInspectScreen({
    required this.attachment,
  });

  final OpenPostSubmissionAttachment attachment;

  static Route<void> route(OpenPostSubmissionAttachment attachment) {
    return PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: _OpenPostDocumentInspectScreen(
            attachment: attachment,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          attachment.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return _OpenPostDocumentViewer(
              attachment: attachment,
              routeDetached: false,
              inspectionMode: true,
              viewportHeight: constraints.maxHeight,
            );
          },
        ),
      ),
    );
  }
}

class _OpenPostDocumentViewer extends StatefulWidget {
  const _OpenPostDocumentViewer({
    required this.attachment,
    required this.routeDetached,
    this.selectionAreaKey,
    this.onSelectionChanged,
    this.contextMenuBuilder,
    this.inspectionMode = false,
    this.viewportHeight,
  });

  final OpenPostSubmissionAttachment attachment;
  final bool routeDetached;
  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final Widget Function(BuildContext, SelectableRegionState)?
      contextMenuBuilder;
  final bool inspectionMode;
  final double? viewportHeight;

  @override
  State<_OpenPostDocumentViewer> createState() =>
      _OpenPostDocumentViewerState();
}

class _OpenPostDocumentViewerState extends State<_OpenPostDocumentViewer> {
  static const double _minimumHeight = 180.0;
  static const double _minimumReaderHeight = 36.0;
  static const double _preferredDocumentHeight = 560.0;
  static const double _maximumHeight = 680.0;

  late double _height;
  double? _previewHeight;
  String? _fullReaderText;
  bool _showIncompletePreviewHint = false;
  bool _isLoading = true;
  bool _hasActiveReaderSelection = false;
  bool _suppressNextInspectorTap = false;
  String? _error;
  Timer? _documentLoadTimeout;
  int _viewerGeneration = 0;

  bool get _isOdt => widget.attachment.extension == 'odt';
  bool get _usesReaderPresentation =>
      !widget.inspectionMode && widget.attachment.usesReaderPresentation;
  bool get _usesDarkReaderColors =>
      !widget.inspectionMode && widget.attachment.usesDarkReaderColors;
  bool get _expandsToContent =>
      !widget.inspectionMode && widget.attachment.expandsPreviewToContent;
  bool get _supportsZoom =>
      widget.inspectionMode && widget.attachment.supportsDocumentZoom;
  bool get _canOpenInspector =>
      !widget.inspectionMode && widget.attachment.supportsDocumentZoom;

  @override
  void initState() {
    super.initState();
    _resetViewerState();
  }

  @override
  void didUpdateWidget(covariant _OpenPostDocumentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.contentUrl != widget.attachment.contentUrl ||
        oldWidget.attachment.viewerUrl != widget.attachment.viewerUrl ||
        oldWidget.attachment.extension != widget.attachment.extension) {
      _viewerGeneration++;
      _resetViewerState();
    } else if (!oldWidget.routeDetached && widget.routeDetached) {
      _viewerGeneration++;
      _cancelDocumentLoadTimeout();
    } else if (oldWidget.routeDetached && !widget.routeDetached) {
      _viewerGeneration++;
      _isLoading = true;
      _error = null;
    }
  }

  @override
  void dispose() {
    _viewerGeneration++;
    _cancelDocumentLoadTimeout();
    super.dispose();
  }

  void _resetViewerState() {
    _cancelDocumentLoadTimeout();
    _height = _minimumHeight;
    _previewHeight = null;
    _fullReaderText = null;
    _showIncompletePreviewHint = false;
    _isLoading = true;
    _hasActiveReaderSelection = false;
    _suppressNextInspectorTap = false;
    _error = null;
  }

  double _displayHeight() {
    final viewportHeight = widget.viewportHeight;
    if (widget.inspectionMode &&
        viewportHeight != null &&
        viewportHeight.isFinite &&
        viewportHeight > 0) {
      return viewportHeight;
    }
    final previewHeight = _previewHeight;
    if (!widget.inspectionMode && previewHeight != null) {
      return previewHeight;
    }
    if (_expandsToContent) {
      return math.max(_minimumReaderHeight, _height);
    }
    final availableHeight = MediaQuery.of(context).size.height * 0.68;
    final maximum = math.max(
      _minimumHeight,
      math.min(_maximumHeight, availableHeight),
    );
    return math.min(_preferredDocumentHeight, maximum);
  }

  bool _isCurrentViewer(int generation) {
    return mounted && generation == _viewerGeneration;
  }

  void _updateHeight(Object? value, int generation) {
    if (!_expandsToContent) return;
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null ||
        !parsed.isFinite ||
        !_isCurrentViewer(generation)) {
      return;
    }
    final nextHeight = math.max(_minimumReaderHeight, parsed.ceilToDouble());
    if ((nextHeight - _height).abs() < 1.0) return;
    setState(() {
      _height = nextHeight;
    });
  }

  void _updatePreviewHeight(Object? value, int generation) {
    if (widget.inspectionMode || !_isCurrentViewer(generation)) return;
    final data = value is Map ? value : null;
    final heightValue = data?['height'] ?? value;
    final parsed = heightValue is num
        ? heightValue.toDouble()
        : double.tryParse(heightValue?.toString() ?? '');
    if (parsed == null || !parsed.isFinite) return;
    final isFullText = data?['mode'] == 'fullText';
    final showIncompletePreviewHint = data?['mode'] == 'truncated';
    final nextHeight = isFullText
        ? math.max(_minimumReaderHeight, parsed.ceilToDouble())
        : parsed
            .clamp(_minimumReaderHeight, _preferredDocumentHeight)
            .toDouble();
    if (_previewHeight != null &&
        (nextHeight - _previewHeight!).abs() < 1.0 &&
        _showIncompletePreviewHint == showIncompletePreviewHint &&
        (isFullText || !_isLoading)) {
      return;
    }
    setState(() {
      _previewHeight = nextHeight;
      _showIncompletePreviewHint = showIncompletePreviewHint;
      if (!isFullText) {
        _isLoading = false;
      }
    });
  }

  void _updateFullReaderText(Object? value, int generation) {
    if (widget.inspectionMode || !_isCurrentViewer(generation)) return;
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == _fullReaderText) return;
    _cancelDocumentLoadTimeout();
    setState(() {
      _fullReaderText = text;
      _previewHeight = null;
      _showIncompletePreviewHint = false;
      _isLoading = false;
      _error = null;
    });
  }

  void _handleReaderSelectionChanged(SelectedContent? content) {
    _hasActiveReaderSelection = content?.plainText.isNotEmpty ?? false;
    widget.onSelectionChanged?.call(content);
  }

  void _handleReaderPointerDown(PointerDownEvent _) {
    _suppressNextInspectorTap = _hasActiveReaderSelection;
  }

  void _handleReaderTap() {
    if (!_canOpenInspector) return;
    if (_suppressNextInspectorTap) {
      _suppressNextInspectorTap = false;
      return;
    }
    unawaited(_openInspector());
  }

  void _setError(String message, int generation) {
    if (!_isCurrentViewer(generation)) return;
    _cancelDocumentLoadTimeout();
    _viewerGeneration++;
    setState(() {
      _isLoading = false;
      _error = message;
    });
  }

  void _cancelDocumentLoadTimeout() {
    _documentLoadTimeout?.cancel();
    _documentLoadTimeout = null;
  }

  Future<void> _openInspector() async {
    await Navigator.of(context).push<void>(
      _OpenPostDocumentInspectScreen.route(widget.attachment),
    );
  }

  Set<Factory<OneSequenceGestureRecognizer>> _viewerGestureRecognizers() {
    if (!_supportsZoom) {
      return <Factory<OneSequenceGestureRecognizer>>{};
    }
    return <Factory<OneSequenceGestureRecognizer>>{
      Factory<OneSequenceGestureRecognizer>(
        () => EagerGestureRecognizer(),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final fullReaderText = _fullReaderText;
    if (!widget.inspectionMode && fullReaderText != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7.0),
        child: ColoredBox(
          color: _attachmentSurfaceColor,
          child: Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                selectionColor:
                    const Color(0xFFE09321).withValues(alpha: 0.4),
                selectionHandleColor: const Color(0xFFE09321),
              ),
            ),
            child: SelectionArea(
              key: widget.selectionAreaKey,
              onSelectionChanged: _handleReaderSelectionChanged,
              contextMenuBuilder: widget.contextMenuBuilder,
              child: Listener(
                onPointerDown: _handleReaderPointerDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _canOpenInspector ? _handleReaderTap : null,
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 12.0),
                    child: Text(
                      fullReaderText,
                      style: const TextStyle(
                        color: Color(0xFFE0E0E0),
                        fontSize: 14.0,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final height = _displayHeight();
    final viewerGeneration = _viewerGeneration;
    if (widget.routeDetached) {
      return ColoredBox(
        color: _attachmentSurfaceColor,
        child: SizedBox(
          width: double.infinity,
          height: height,
        ),
      );
    }
    if (_error != null) {
      return SizedBox(
        width: double.infinity,
        height: _minimumHeight,
        child: _AttachmentFallback(
          icon: Icons.error_outline,
          message: _error!,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(7.0),
      child: ColoredBox(
        color: _attachmentSurfaceColor,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _canOpenInspector,
                  child: InAppWebView(
                gestureRecognizers: _viewerGestureRecognizers(),
                key: ValueKey<String>(
                  '${widget.attachment.contentUrl}|${widget.attachment.viewerUrl ?? ''}|${widget.inspectionMode}',
                ),
                initialData: _isOdt
                    ? InAppWebViewInitialData(
                        data: _odtHtml(),
                        baseUrl: WebUri('https://www.furaffinity.net'),
                        encoding: 'utf-8',
                        mimeType: 'text/html',
                      )
                    : null,
                initialUrlRequest: _isOdt
                    ? null
                    : URLRequest(
                        url: WebUri(widget.attachment.viewerUrl!),
                      ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  disableVerticalScroll:
                      _expandsToContent || _canOpenInspector,
                  disableHorizontalScroll: !_supportsZoom,
                  verticalScrollBarEnabled: _supportsZoom,
                  horizontalScrollBarEnabled: false,
                  supportZoom: _supportsZoom,
                  builtInZoomControls: _supportsZoom,
                  displayZoomControls: false,
                  useWideViewPort: _supportsZoom,
                  loadWithOverviewMode: _supportsZoom,
                  enableViewportScale: _supportsZoom,
                  ignoresViewportScaleLimits: _supportsZoom,
                  minimumZoomScale: 1.0,
                  maximumZoomScale: _supportsZoom ? 4.0 : 1.0,
                  useHybridComposition: false,
                  transparentBackground: true,
                ),
                onWebViewCreated: (controller) {
                  if (_isOdt) {
                    _cancelDocumentLoadTimeout();
                    _documentLoadTimeout = Timer(
                      const Duration(seconds: 15),
                      () {
                        if (!_isCurrentViewer(viewerGeneration)) return;
                        _setError(
                          'Unable to preview this ODT file. Download the original file to open it.',
                          viewerGeneration,
                        );
                      },
                    );
                  }
                  controller.addJavaScriptHandler(
                    handlerName: 'openPostDocumentHeight',
                    callback: (arguments) {
                      if (_isCurrentViewer(viewerGeneration) &&
                          arguments.isNotEmpty) {
                        _updateHeight(arguments.first, viewerGeneration);
                      }
                    },
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'openPostDocumentPreviewHeight',
                    callback: (arguments) {
                      if (_isCurrentViewer(viewerGeneration) &&
                          arguments.isNotEmpty) {
                        _updatePreviewHeight(
                          arguments.first,
                          viewerGeneration,
                        );
                      }
                    },
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'openPostDocumentFullText',
                    callback: (arguments) {
                      if (_isCurrentViewer(viewerGeneration) &&
                          arguments.isNotEmpty) {
                        _updateFullReaderText(
                          arguments.first,
                          viewerGeneration,
                        );
                      }
                    },
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'openPostDocumentError',
                    callback: (arguments) {
                      if (!_isCurrentViewer(viewerGeneration)) return;
                      final message = arguments.isEmpty
                          ? 'Unable to preview this file. Download the original file to open it.'
                          : arguments.first.toString();
                      _setError(message, viewerGeneration);
                    },
                  );
                  controller.addJavaScriptHandler(
                    handlerName: 'openPostDocumentReady',
                    callback: (arguments) {
                      if (!_isCurrentViewer(viewerGeneration)) return;
                      _cancelDocumentLoadTimeout();
                      if (_usesReaderPresentation &&
                          _fullReaderText == null &&
                          _isLoading) {
                        setState(() {
                          _isLoading = false;
                        });
                      }
                    },
                  );
                },
                onLoadStop: (controller, url) async {
                  if (!_isCurrentViewer(viewerGeneration)) return;
                  try {
                    await controller.injectCSSCode(
                      source: _documentViewerCss(
                        usesReaderPresentation: _usesReaderPresentation,
                        usesDarkReaderColors: _usesDarkReaderColors,
                        expandsToContent: _expandsToContent,
                        inspectionMode: widget.inspectionMode,
                      ),
                    );
                    if (!_isCurrentViewer(viewerGeneration)) return;
                    if (!_isOdt) {
                      await controller.evaluateJavascript(
                        source: _documentViewerSetupScript(
                          expandsToContent: _expandsToContent,
                          supportsZoom: _supportsZoom,
                          usesReaderPresentation: _usesReaderPresentation,
                          inspectionMode: widget.inspectionMode,
                        ),
                      );
                    }
                    if (_isCurrentViewer(viewerGeneration) &&
                        !_usesReaderPresentation) {
                      setState(() {
                        _isLoading = false;
                      });
                    }
                  } catch (_) {
                    if (!_isCurrentViewer(viewerGeneration)) return;
                    _setError(
                      'Unable to preview this file. Download the original file to open it.',
                      viewerGeneration,
                    );
                  }
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  if (!_isCurrentViewer(viewerGeneration)) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  if (navigationAction.isForMainFrame == false) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  final url = navigationAction.request.url?.toString();
                  if (Platform.isAndroid) {
                    if (url != null && url.isNotEmpty) {
                      await handleFALink(context, url);
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  if (Platform.isIOS &&
                      navigationAction.navigationType ==
                          NavigationType.LINK_ACTIVATED) {
                    if (url != null && url.isNotEmpty) {
                      await handleFALink(context, url);
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onReceivedError: (controller, request, error) {
                  if (!_isCurrentViewer(viewerGeneration)) return;
                  if (request.isForMainFrame == false) return;
                  _setError(
                    'Unable to preview this file. Download the original file to open it.',
                    viewerGeneration,
                  );
                },
                onReceivedHttpError: (controller, request, errorResponse) {
                  if (!_isCurrentViewer(viewerGeneration)) return;
                  if (request.isForMainFrame == false) return;
                  _setError(
                    'Unable to preview this file. HTTP ${errorResponse.statusCode}.',
                    viewerGeneration,
                  );
                },
              ),
            ),
              ),
              if (_canOpenInspector && !_isLoading)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openInspector,
                  ),
                ),
              if (_showIncompletePreviewHint && !_isLoading)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 76,
                  child: IgnorePointer(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                _attachmentSurfaceColor.withValues(alpha: 0.05),
                                _attachmentSurfaceColor.withValues(alpha: 0.92),
                              ],
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFFE09321),
                              size: 38,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_isLoading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: _attachmentSurfaceColor,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFE09321),
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _odtHtml() {
    final documentUrl = jsonEncode(widget.attachment.contentUrl);
    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=4,user-scalable=yes">
<style>
html,body{margin:0;padding:0;background:#151515;color:#e0e0e0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
#status{padding:28px 16px;text-align:center}
#document{width:100%;overflow:hidden;background:#fff;color:#000}
</style>
<script src="https://www.furaffinity.net/themes/beta/js/compiled/webodf.0.5.9.min.js"></script>
</head>
<body>
<div id="status">Loading document…</div>
<div id="document"></div>
<script>
(function(){
  const host=document.getElementById('document');
  const status=document.getElementById('status');
  let ready=false;
  let failed=false;
  let reportScheduled=false;
  function report(){
    const height=Math.max(
      document.body.scrollHeight,
      document.documentElement.scrollHeight,
      host.scrollHeight,
      180
    );
    if(window.flutter_inappwebview){
      window.flutter_inappwebview.callHandler('openPostDocumentHeight',height);
    }
  }
  function scheduleReport(){
    if(reportScheduled){
      return;
    }
    reportScheduled=true;
    requestAnimationFrame(function(){
      reportScheduled=false;
      report();
    });
  }
  function fail(message){
    if(failed||ready){
      return;
    }
    failed=true;
    status.textContent=message;
    if(window.flutter_inappwebview){
      window.flutter_inappwebview.callHandler('openPostDocumentError',message);
    }
  }
  try{
    if(!window.odf||!window.odf.OdfCanvas){
      fail('Unable to preview this ODT file. Download the original file to open it.');
      return;
    }
    const canvas=new window.odf.OdfCanvas(host);
    canvas.addListener('statereadychange',function(){
      if(ready){
        return;
      }
      ready=true;
      if(window.flutter_inappwebview){
        window.flutter_inappwebview.callHandler('openPostDocumentReady');
      }
      if(status.isConnected){
        status.remove();
      }
      try{
        canvas.fitToWidth(host.clientWidth);
      }catch(_){}
      scheduleReport();
      setTimeout(scheduleReport,250);
      setTimeout(scheduleReport,1000);
    });
    canvas.load($documentUrl);
    new MutationObserver(scheduleReport).observe(document.body,{
      childList:true,
      subtree:true
    });
    if(window.ResizeObserver){
      new ResizeObserver(scheduleReport).observe(host);
    }
    window.addEventListener('resize',function(){
      try{
        canvas.fitToWidth(host.clientWidth);
      }catch(_){}
      scheduleReport();
    });
  }catch(error){
    fail('Unable to preview this ODT file. Download the original file to open it.');
  }
})();
</script>
</body>
</html>
''';
  }
}

String _documentViewerCss({
  required bool usesReaderPresentation,
  required bool usesDarkReaderColors,
  required bool expandsToContent,
  required bool inspectionMode,
}) {
  final readerCss = usesReaderPresentation
      ? '''
body,pre,code{color:#e0e0e0!important;font-size:14px!important;line-height:1.4!important}
pre{margin:0!important;padding:12px!important;white-space:pre-wrap!important;overflow-wrap:anywhere!important}
#openPostReader{padding:0 12px;color:#e0e0e0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:14px;line-height:1.4}
.openPostReaderPage+.openPostReaderPage{margin-top:14px}
.openPostReaderLine{min-height:19.6px;white-space:pre-wrap;overflow-wrap:anywhere}
html.openPostFullTextReader,
html.openPostFullTextReader body{height:auto!important;min-height:0!important;overflow:hidden!important}
html.openPostFullTextReader #outerContainer,
html.openPostFullTextReader #mainContainer,
html.openPostFullTextReader #viewerContainer{position:relative!important;inset:auto!important;width:100%!important;height:auto!important;min-height:0!important;overflow:visible!important}
'''
      : '';
  final darkReaderCss = usesDarkReaderColors
      ? '''
.pdfViewer .page{background:#151515!important;border:0!important;box-shadow:none!important}
.pdfViewer .page canvas,
.pdfViewer .page svg{filter:invert(1)!important;mix-blend-mode:screen!important;opacity:.868!important}
'''
      : '';
  final expandedCss = expandsToContent
      ? '''
html,body{height:auto!important;min-height:0!important;overflow:hidden!important}
#outerContainer,
#mainContainer,
#viewerContainer{position:relative!important;inset:auto!important;width:100%!important;height:auto!important;min-height:0!important;overflow:visible!important}
#viewerContainer{overflow:hidden!important}
#viewer{min-height:0!important;padding:0!important}
.pdfViewer{padding-bottom:0!important}
'''
      : '';
  final inspectionCss = inspectionMode
      ? '''
html,body,#outerContainer,#mainContainer,#viewerContainer{height:100%!important}
#viewer.openPostInspectionSinglePage{display:flex!important;flex-direction:column!important;min-height:100%!important}
#viewer.openPostInspectionSinglePage .page{flex:none!important;margin-block:auto!important;margin-inline:auto!important}
'''
      : '';
  return '''
html,body{margin:0!important;padding:0!important;background:#151515!important;color:#e0e0e0!important}
:root{--toolbar-height:0px!important}
#toolbarContainer,
#secondaryToolbar,
#sidebarContainer,
#loadingBar,
#viewFind{display:none!important}
#outerContainer,
#mainContainer,
#viewerContainer{background:#151515!important}
#viewerContainer{top:0!important;inset-block-start:0!important}
#outerContainer.sidebarOpen #viewerContainer{inset-inline-start:0!important}
#mainContainer{min-width:0!important}
$readerCss
$darkReaderCss
$expandedCss
$inspectionCss
''';
}

String _documentViewerSetupScript({
  required bool expandsToContent,
  required bool supportsZoom,
  required bool usesReaderPresentation,
  required bool inspectionMode,
}) {
  return '''
(function(){
  const expandsToContent=$expandsToContent;
  const supportsZoom=$supportsZoom;
  const usesReaderPresentation=$usesReaderPresentation;
  const inspectionMode=$inspectionMode;
  let viewport=document.querySelector('meta[name="viewport"]');
  if(!viewport){
    viewport=document.createElement('meta');
    viewport.name='viewport';
    document.head.appendChild(viewport);
  }
  viewport.content=supportsZoom
    ? 'width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=4,user-scalable=yes'
    : 'width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no';
  if((!expandsToContent&&!usesReaderPresentation&&!inspectionMode)||
      window.__openPostDocumentHeightObserver){
    return;
  }
  window.__openPostDocumentHeightObserver=true;
  let reportScheduled=false;
  let observedTarget=null;
  let eventBusBound=false;
  let readerSignature='';
  let readerSignatureSince=0;
  let readerRetryScheduled=false;
  let pageWidthApplied=false;
  let pdfClassificationStarted=false;
  let pdfPreviewMode=null;
  let readerTextReported=false;
  let readerFallbackReady=false;
  const readerStartedAt=Date.now();
  const resizeObserver=window.ResizeObserver
    ? new ResizeObserver(scheduleOpenPostDocumentHeight)
    : null;
  function readerTarget(){
    return document.getElementById('openPostReader')||
      document.getElementById('viewer')||
      document.querySelector('pre')||
      document.querySelector('article')||
      document.querySelector('main')||
      document.body;
  }
  function observeTarget(target){
    if(!resizeObserver||!target||target===observedTarget){
      return;
    }
    resizeObserver.disconnect();
    resizeObserver.observe(target);
    observedTarget=target;
  }
  function applyPdfPageLayout(){
    if(!inspectionMode&&!(usesReaderPresentation&&!expandsToContent)){
      return;
    }
    const app=window.PDFViewerApplication;
    const pdfViewer=app&&app.pdfViewer;
    const viewer=document.getElementById('viewer');
    if(!pdfViewer||!viewer){
      return;
    }
    const pages=viewer.querySelectorAll('.page');
    if(pages.length===0){
      return;
    }
    if(inspectionMode){
      viewer.classList.toggle(
        'openPostInspectionSinglePage',
        pages.length===1
      );
    }
    if(!pageWidthApplied){
      try{
        pdfViewer.currentScaleValue='page-width';
        pageWidthApplied=true;
      }catch(_){}
    }
  }
  function scheduleReaderRetry(){
    if(readerRetryScheduled){
      return;
    }
    readerRetryScheduled=true;
    setTimeout(function(){
      readerRetryScheduled=false;
      scheduleOpenPostDocumentHeight();
    },220);
  }
  function readerLines(textLayer){
    const items=[];
    for(const node of textLayer.querySelectorAll('span')){
      const value=(node.textContent||'').replace(/\\s+/g,' ').trim();
      if(!value){
        continue;
      }
      const rect=node.getBoundingClientRect();
      if(rect.width<=0||rect.height<=0){
        continue;
      }
      items.push({
        value:value,
        left:rect.left,
        right:rect.right,
        top:rect.top,
        bottom:rect.bottom,
        height:rect.height,
        center:rect.top+rect.height/2
      });
    }
    items.sort(function(a,b){
      const vertical=a.center-b.center;
      return Math.abs(vertical)>2?vertical:a.left-b.left;
    });
    const lines=[];
    for(const item of items){
      const last=lines.length>0?lines[lines.length-1]:null;
      const tolerance=last?Math.max(2,Math.min(last.height,item.height)*0.35):0;
      if(!last||Math.abs(last.center-item.center)>tolerance){
        lines.push({
          items:[item],
          center:item.center,
          top:item.top,
          bottom:item.bottom,
          height:item.height
        });
        continue;
      }
      last.items.push(item);
      last.center=(last.center*(last.items.length-1)+item.center)/last.items.length;
      last.top=Math.min(last.top,item.top);
      last.bottom=Math.max(last.bottom,item.bottom);
      last.height=Math.max(last.height,item.height);
    }
    return lines;
  }
  function readerLineText(line){
    line.items.sort(function(a,b){return a.left-b.left;});
    let text='';
    let right=null;
    for(const item of line.items){
      const gap=right===null?0:item.left-right;
      if(text&&gap>Math.max(1,item.height*0.12)&&
          !'.,;:!?)]}'.includes(item.value.charAt(0))){
        text+=' ';
      }
      text+=item.value;
      right=right===null?item.right:Math.max(right,item.right);
    }
    return text;
  }
  function pdfTextLines(items){
    const positioned=[];
    for(const item of items){
      const value=(item.str||'').replace(/\\s+/g,' ').trim();
      if(!value){
        continue;
      }
      const transform=item.transform||[];
      const left=Number(transform[4])||0;
      const center=Number(transform[5])||0;
      const height=Math.max(
        1,
        Math.abs(Number(transform[3]))||Number(item.height)||12
      );
      const width=Math.max(0,Number(item.width)||0);
      positioned.push({
        value:value,
        left:left,
        right:left+width,
        center:center,
        height:height,
        hasEOL:item.hasEOL===true
      });
    }
    positioned.sort(function(a,b){
      const vertical=b.center-a.center;
      return Math.abs(vertical)>2?vertical:a.left-b.left;
    });
    const lines=[];
    for(const item of positioned){
      const last=lines.length>0?lines[lines.length-1]:null;
      const tolerance=last
        ? Math.max(2,Math.min(last.height,item.height)*0.4)
        : 0;
      if(!last||Math.abs(last.center-item.center)>tolerance){
        lines.push({
          items:[item],
          center:item.center,
          height:item.height
        });
        continue;
      }
      last.items.push(item);
      last.center=(last.center*(last.items.length-1)+item.center)/last.items.length;
      last.height=Math.max(last.height,item.height);
    }
    return lines;
  }
  function pdfLineText(line){
    line.items.sort(function(a,b){return a.left-b.left;});
    let text='';
    let right=null;
    for(const item of line.items){
      const gap=right===null?0:item.left-right;
      if(text&&gap>Math.max(1,item.height*0.12)&&
          !'.,;:!?)]}'.includes(item.value.charAt(0))){
        text+=' ';
      }
      text+=item.value;
      right=right===null?item.right:Math.max(right,item.right);
    }
    return text;
  }
  function reportFullReaderText(fullTextPages){
    const fullText=fullTextPages.join('\\n\\n').trim();
    if(fullText&&window.flutter_inappwebview){
      readerTextReported=true;
      window.flutter_inappwebview.callHandler(
        'openPostDocumentFullText',
        fullText
      );
    }
  }
  function normalizedDocumentText(target){
    if(!target){
      return '';
    }
    let value=target.innerText||'';
    if(!value&&typeof target.cloneNode==='function'){
      const clone=target.cloneNode(true);
      for(const node of clone.querySelectorAll('script,style,noscript')){
        node.remove();
      }
      value=clone.textContent||'';
    }
    return value
      .replace(/\\u00a0/g,' ')
      .replace(/\\r\\n?/g,'\\n')
      .replace(/[ \\t]+\\n/g,'\\n')
      .replace(/\\n[ \\t]+/g,'\\n')
      .trim();
  }
  function reportDocumentReaderText(){
    if(readerTextReported){
      return true;
    }
    const viewer=document.getElementById('viewer');
    const candidates=[
      viewer&&viewer.querySelector('pre'),
      viewer&&viewer.querySelector('article'),
      viewer&&viewer.querySelector('main'),
      viewer,
      document.querySelector('pre'),
      document.querySelector('article'),
      document.querySelector('main'),
      document.body
    ];
    for(const frame of document.querySelectorAll('iframe')){
      try{
        const frameDocument=frame.contentDocument;
        if(frameDocument){
          candidates.push(
            frameDocument.querySelector('pre'),
            frameDocument.querySelector('article'),
            frameDocument.querySelector('main'),
            frameDocument.body
          );
        }
      }catch(_){}
    }
    const visited=new Set();
    let text='';
    for(const target of candidates){
      if(!target||visited.has(target)){
        continue;
      }
      visited.add(target);
      const candidate=normalizedDocumentText(target);
      if(candidate&&!/^loading(?:\\.\\.\\.)?\$/i.test(candidate)){
        text=candidate;
        break;
      }
    }
    if(!text){
      scheduleReaderRetry();
      return false;
    }
    const signature='document:'+text.length+':'+
      text.slice(0,64)+':'+text.slice(-64);
    const now=Date.now();
    if(signature!==readerSignature){
      readerSignature=signature;
      readerSignatureSince=now;
      scheduleReaderRetry();
      return false;
    }
    if(now-readerSignatureSince<180){
      scheduleReaderRetry();
      return false;
    }
    reportFullReaderText([text]);
    return readerTextReported;
  }
  function reportReaderFallbackReady(){
    if(readerTextReported||readerFallbackReady||
        Date.now()-readerStartedAt<2000){
      return;
    }
    const target=readerTarget();
    if(!target||target.getBoundingClientRect().height<=0||
        !window.flutter_inappwebview){
      return;
    }
    readerFallbackReady=true;
    window.flutter_inappwebview.callHandler('openPostDocumentReady');
  }
  function buildReaderFromTextContents(pageContents){
    const existing=document.getElementById('openPostReader');
    if(existing){
      return existing;
    }
    const viewer=document.getElementById('viewer');
    if(!viewer||!viewer.parentNode){
      return null;
    }
    const reader=document.createElement('div');
    reader.id='openPostReader';
    let hasText=false;
    const fullTextPages=[];
    for(const items of pageContents){
      const lines=pdfTextLines(items);
      if(lines.length===0){
        continue;
      }
      hasText=true;
      const page=document.createElement('div');
      page.className='openPostReaderPage';
      const pageTextLines=[];
      let previous=null;
      for(const line of lines){
        const lineElement=document.createElement('div');
        lineElement.className='openPostReaderLine';
        const lineText=pdfLineText(line);
        lineElement.textContent=lineText;
        if(previous){
          const gap=Math.abs(previous.center-line.center);
          if(gap>Math.max(previous.height,line.height)*1.6){
            lineElement.style.marginTop='19.6px';
            pageTextLines.push('');
          }
        }
        page.appendChild(lineElement);
        pageTextLines.push(lineText);
        previous=line;
      }
      reader.appendChild(page);
      fullTextPages.push(pageTextLines.join('\\n'));
    }
    if(!hasText){
      return null;
    }
    document.documentElement.classList.add('openPostFullTextReader');
    viewer.parentNode.insertBefore(reader,viewer);
    viewer.style.setProperty('display','none','important');
    reportFullReaderText(fullTextPages);
    return reader;
  }
  function imageOperatorSet(){
    const pdfjs=window.pdfjsLib;
    const ops=pdfjs&&pdfjs.OPS;
    if(ops){
      const values=new Set([
        ops.paintImageMaskXObject,
        ops.paintImageMaskXObjectGroup,
        ops.paintImageXObject,
        ops.paintInlineImageXObject,
        ops.paintInlineImageXObjectGroup,
        ops.paintImageXObjectRepeat,
        ops.paintImageMaskXObjectRepeat,
        ops.paintSolidColorImageMask
      ].filter(function(value){return typeof value==='number';}));
      if(values.size>0){
        return values;
      }
    }
    return new Set([83,84,85,86,87,88,89,90]);
  }
  function reportFullTextReaderHeight(){
    const reader=document.getElementById('openPostReader');
    if(!reader||!window.flutter_inappwebview){
      return;
    }
    const rect=reader.getBoundingClientRect();
    const height=Math.ceil(Math.max(rect.height,reader.scrollHeight)+12);
    if(height>0){
      window.flutter_inappwebview.callHandler(
        'openPostDocumentPreviewHeight',
        {mode:'fullText',height:height}
      );
    }
  }
  function reportVisualPdfPreview(mode){
    if(inspectionMode||expandsToContent){
      return;
    }
    const viewerContainer=document.getElementById('viewerContainer');
    const viewer=document.getElementById('viewer');
    const page=viewer?viewer.querySelector('.page'):null;
    if(!viewerContainer||!page||!window.flutter_inappwebview){
      return;
    }
    const containerRect=viewerContainer.getBoundingClientRect();
    const pageRect=page.getBoundingClientRect();
    const height=Math.ceil(pageRect.bottom-containerRect.top+12);
    if(height>0){
      window.flutter_inappwebview.callHandler(
        'openPostDocumentPreviewHeight',
        {mode:mode,height:height}
      );
    }
  }
  async function classifyPdfPreview(){
    if(pdfClassificationStarted||inspectionMode||expandsToContent||
        !usesReaderPresentation){
      return;
    }
    const app=window.PDFViewerApplication;
    const pdfDocument=app&&app.pdfDocument;
    if(!pdfDocument){
      return;
    }
    pdfClassificationStarted=true;
    try{
      const pageContents=[];
      const imageOps=imageOperatorSet();
      let hasText=false;
      let hasImages=false;
      for(let pageNumber=1;pageNumber<=pdfDocument.numPages;pageNumber++){
        const page=await pdfDocument.getPage(pageNumber);
        const textContent=await page.getTextContent();
        const items=Array.isArray(textContent.items)?textContent.items:[];
        pageContents.push(items);
        if(items.some(function(item){
          return !!(item.str||'').trim();
        })){
          hasText=true;
        }
        const operatorList=await page.getOperatorList();
        const operators=operatorList&&operatorList.fnArray
          ? Array.from(operatorList.fnArray)
          : [];
        if(operators.some(function(operator){return imageOps.has(operator);})){
          hasImages=true;
        }
      }
      if(hasText&&!hasImages&&buildReaderFromTextContents(pageContents)){
        pdfPreviewMode='fullText';
      }else{
        pdfPreviewMode=(hasText&&hasImages)||pdfDocument.numPages>1
          ? 'truncated'
          : 'preview';
      }
    }catch(_){
      pdfPreviewMode='truncated';
    }
    scheduleOpenPostDocumentHeight();
  }
  function buildReaderFromPdf(){
    if(!usesReaderPresentation||document.getElementById('openPostReader')){
      return;
    }
    const viewer=document.getElementById('viewer');
    if(!viewer){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    const pages=Array.from(viewer.querySelectorAll('.page'));
    if(pages.length===0){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    const pageLayers=pages.map(function(page){
      return page.querySelector('.textLayer');
    });
    if(expandsToContent&&pageLayers.some(function(layer){return !layer;})){
      return;
    }
    let layers=pageLayers.filter(function(layer){return !!layer;});
    if(layers.length===0){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    if(!expandsToContent){
      layers=layers.slice(0,1);
    }
    const signature=layers.map(function(layer){
      const spans=layer.querySelectorAll('span');
      return spans.length+':'+(layer.textContent||'').length;
    }).join('|');
    if(!signature||signature===pages.length+':0'){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    const now=Date.now();
    if(signature!==readerSignature){
      readerSignature=signature;
      readerSignatureSince=now;
      scheduleReaderRetry();
      return;
    }
    if(now-readerSignatureSince<180){
      scheduleReaderRetry();
      return;
    }
    const reader=document.createElement('div');
    reader.id='openPostReader';
    let hasText=false;
    const fullTextPages=[];
    for(const layer of layers){
      const lines=readerLines(layer);
      if(lines.length===0){
        continue;
      }
      hasText=true;
      const page=document.createElement('div');
      page.className='openPostReaderPage';
      const pageTextLines=[];
      let previous=null;
      for(const line of lines){
        const lineElement=document.createElement('div');
        lineElement.className='openPostReaderLine';
        const lineText=readerLineText(line);
        lineElement.textContent=lineText;
        if(previous){
          const gap=line.top-previous.bottom;
          if(gap>Math.max(previous.height,line.height)*0.8){
            lineElement.style.marginTop='19.6px';
            pageTextLines.push('');
          }
        }
        page.appendChild(lineElement);
        pageTextLines.push(lineText);
        previous=line;
      }
      reader.appendChild(page);
      fullTextPages.push(pageTextLines.join('\\n'));
    }
    if(!hasText||!viewer.parentNode){
      if(expandsToContent){
        reportDocumentReaderText();
      }
      return;
    }
    viewer.parentNode.insertBefore(reader,viewer);
    viewer.style.setProperty('display','none','important');
    reportFullReaderText(fullTextPages);
  }
  function trimLastReaderPage(){
    if(document.getElementById('openPostReader')){
      return;
    }
    const viewer=document.getElementById('viewer');
    if(!viewer){
      return;
    }
    const pages=viewer.querySelectorAll('.page');
    const page=pages.length>0?pages[pages.length-1]:null;
    const textLayer=page?page.querySelector('.textLayer'):null;
    if(!page||!textLayer){
      return;
    }
    const pageRect=page.getBoundingClientRect();
    let contentBottom=0;
    for(const node of textLayer.querySelectorAll('span')){
      if(!(node.textContent||'').trim()){
        continue;
      }
      const rect=node.getBoundingClientRect();
      if(rect.width<=0||rect.height<=0){
        continue;
      }
      contentBottom=Math.max(contentBottom,rect.bottom-pageRect.top);
    }
    if(contentBottom<=0){
      return;
    }
    const height=Math.max(36,Math.ceil(contentBottom+16));
    const heightValue=height+'px';
    if(page.dataset.openPostReaderHeight===heightValue){
      return;
    }
    page.dataset.openPostReaderHeight=heightValue;
    page.style.setProperty('height',heightValue,'important');
    page.style.setProperty('min-height','0','important');
  }
  function bindEventBus(){
    const app=window.PDFViewerApplication;
    const eventBus=app&&app.eventBus;
    if(eventBusBound||!eventBus||typeof eventBus.on!=='function'){
      return;
    }
    eventBusBound=true;
    eventBus.on('pagesinit',scheduleOpenPostDocumentHeight);
    eventBus.on('pagesloaded',scheduleOpenPostDocumentHeight);
    eventBus.on('pagerendered',scheduleOpenPostDocumentHeight);
    eventBus.on('textlayerrendered',scheduleOpenPostDocumentHeight);
    eventBus.on('scalechanging',scheduleOpenPostDocumentHeight);
  }
  function reportOpenPostDocumentHeight(){
    bindEventBus();
    applyPdfPageLayout();
    if(usesReaderPresentation&&!expandsToContent){
      classifyPdfPreview();
      if(pdfPreviewMode==='fullText'){
        reportFullTextReaderHeight();
      }else if(pdfPreviewMode){
        reportVisualPdfPreview(pdfPreviewMode);
      }
      return;
    }
    buildReaderFromPdf();
    if(!expandsToContent){
      return;
    }
    if(usesReaderPresentation&&!readerTextReported){
      reportReaderFallbackReady();
    }
    trimLastReaderPage();
    const target=readerTarget();
    if(!target){
      return;
    }
    observeTarget(target);
    const rect=target.getBoundingClientRect();
    if(rect.width<=0||rect.height<=0){
      return;
    }
    const height=Math.ceil(rect.bottom+window.scrollY)+1;
    if(height>0&&window.flutter_inappwebview){
      window.flutter_inappwebview.callHandler('openPostDocumentHeight',height);
    }
  }
  function scheduleOpenPostDocumentHeight(){
    if(reportScheduled){
      return;
    }
    reportScheduled=true;
    requestAnimationFrame(function(){
      reportScheduled=false;
      reportOpenPostDocumentHeight();
    });
  }
  if(window.MutationObserver&&document.body){
    new MutationObserver(scheduleOpenPostDocumentHeight).observe(document.body,{
      childList:true,
      characterData:true,
      subtree:true
    });
  }
  if(document.fonts&&document.fonts.ready){
    document.fonts.ready.then(scheduleOpenPostDocumentHeight);
  }
  window.addEventListener('resize',scheduleOpenPostDocumentHeight);
  setTimeout(scheduleOpenPostDocumentHeight,50);
  setTimeout(scheduleOpenPostDocumentHeight,300);
  setTimeout(scheduleOpenPostDocumentHeight,1000);
  setTimeout(scheduleOpenPostDocumentHeight,2500);
  setTimeout(scheduleOpenPostDocumentHeight,5000);
  scheduleOpenPostDocumentHeight();
})();
''';
}
