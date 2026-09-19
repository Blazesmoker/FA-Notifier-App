import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/data/submission_attachment_html_builder.dart';
import 'package:fanotifier/features/submissions/data/submission_document_webview_scripts.dart';
import 'package:fanotifier/features/submissions/data/submission_document_webview_styles.dart';
import 'package:fanotifier/features/submissions/domain/submission_attachment.dart';
import 'package:fanotifier/features/submissions/presentation/submission_document_inspect_screen.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_attachment_fallback.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_attachment_styles.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';

class SubmissionDocumentViewer extends StatefulWidget {
  const SubmissionDocumentViewer({
    super.key,
    required this.attachment,
    required this.routeDetached,
    this.selectionAreaKey,
    this.onSelectionChanged,
    this.contextMenuBuilder,
    this.inspectionMode = false,
    this.viewportHeight,
  });

  final SubmissionAttachment attachment;
  final bool routeDetached;
  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final Widget Function(BuildContext, SelectableRegionState)?
      contextMenuBuilder;
  final bool inspectionMode;
  final double? viewportHeight;

  @override
  State<SubmissionDocumentViewer> createState() =>
      _SubmissionDocumentViewerState();
}

class _SubmissionDocumentViewerState extends State<SubmissionDocumentViewer> {
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
  void didUpdateWidget(covariant SubmissionDocumentViewer oldWidget) {
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
      SubmissionDocumentInspectScreen.route(widget.attachment),
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
          color: attachmentSurfaceColor,
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
        color: attachmentSurfaceColor,
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
        child: AttachmentFallback(
          icon: Icons.error_outline,
          message: _error!,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(7.0),
      child: ColoredBox(
        color: attachmentSurfaceColor,
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
                        data: buildSubmissionOdtHtml(widget.attachment.contentUrl),
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
                      source: documentViewerCss(
                        usesReaderPresentation: _usesReaderPresentation,
                        usesDarkReaderColors: _usesDarkReaderColors,
                        expandsToContent: _expandsToContent,
                        inspectionMode: widget.inspectionMode,
                      ),
                    );
                    if (!_isCurrentViewer(viewerGeneration)) return;
                    if (!_isOdt) {
                      await controller.evaluateJavascript(
                        source: documentViewerSetupScript(
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
                                attachmentSurfaceColor.withValues(alpha: 0.05),
                                attachmentSurfaceColor.withValues(alpha: 0.92),
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
                    color: attachmentSurfaceColor,
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

}
