import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:FANotifier/features/submissions/domain/submission_description_repository.dart';
import 'package:FANotifier/features/submissions/domain/submission_description_webview_content.dart';
import 'package:FANotifier/shared/fa/fa_webview_document_scripts.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/shared/navigation/fa_link_handler.dart';
import 'package:FANotifier/shared/utils/utils.dart';

class SubmissionDescriptionWebView extends StatefulWidget {
  final String submissionId;
  final String? initialHtml;
  final VoidCallback? onDispose;
  final bool forceHybridComposition;
  final bool enableTextSelection;
  final bool enableScrollPerformancePause;
  final bool fillAvailableHeight;
  final void Function(double height)? onHeightChanged;
  final bool routeDetached;
  final SubmissionDescriptionRepository? repository;

  const SubmissionDescriptionWebView({
    required this.submissionId,
    this.initialHtml,
    this.onDispose,
    this.forceHybridComposition = false,
    this.enableTextSelection = false,
    this.enableScrollPerformancePause = true,
    this.fillAvailableHeight = false,
    this.onHeightChanged,
    this.routeDetached = false,
    this.repository,
    Key? key,
  }) : super(key: key);

  @override
  SubmissionDescriptionWebViewState createState() =>
      SubmissionDescriptionWebViewState();
}

class SubmissionDescriptionWebViewState
    extends State<SubmissionDescriptionWebView>
    with AutomaticKeepAliveClientMixin<SubmissionDescriptionWebView> {
  static const Color background = Color(0xFF121212);

  late final SubmissionDescriptionRepository _submissionDescriptionRepository;
  late Future<SubmissionDescriptionWebViewContent>
      _submissionDescriptionFuture;
  InAppWebViewController? _controller;
  double _webViewHeight = 50.0;
  static const Duration _scrollWebViewResumeDelay =
      Duration(milliseconds: 50);
  Timer? _scrollWebViewResumeTimer;
  bool _isPausedForScroll = false;
  bool _mountWebView = true;

  String? _submissionDescriptionHtml;

  @override
  void initState() {
    super.initState();
    _submissionDescriptionRepository = widget.repository ??
        context.read<SubmissionDescriptionRepository>();
    _mountWebView = !widget.routeDetached;
    if (widget.initialHtml != null) {
      _submissionDescriptionFuture = _processInitialHtml(widget.initialHtml!);
    } else {
      _submissionDescriptionFuture = _fetchCleanHTML();
    }
  }

  @override
  void didUpdateWidget(covariant SubmissionDescriptionWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.submissionId != widget.submissionId ||
        oldWidget.initialHtml != widget.initialHtml) {
      _controller = null;
      if (widget.initialHtml != null) {
        _submissionDescriptionFuture = _processInitialHtml(widget.initialHtml!);
      } else {
        _submissionDescriptionFuture = _fetchCleanHTML();
      }
    }
    final shouldMount = !widget.routeDetached;
    if (_mountWebView != shouldMount) {
      _mountWebView = shouldMount;
      if (!shouldMount) {
        _controller = null;
      }
    }
  }

  @override
  void dispose() {
    _scrollWebViewResumeTimer?.cancel();
    _controller = null;
    if (widget.onDispose != null) {
      widget.onDispose!();
    }
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  void detachWebView() {
    if (!_mountWebView) {
      return;
    }
    if (mounted) {
      setState(() {
        _mountWebView = false;
      });
    } else {
      _mountWebView = false;
    }
    _controller = null;
  }

  void restoreWebView() {
    if (_mountWebView) {
      return;
    }
    if (mounted) {
      setState(() {
        _mountWebView = true;
      });
    } else {
      _mountWebView = true;
    }
  }

  Future<void> _pauseWebView() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      if (Platform.isAndroid) {
        await controller.pause();
      } else if (Platform.isIOS) {
        await controller.pauseTimers();
      }
    } catch (e) {
      debugPrint('Failed to pause submission WebView: $e');
    }
  }

  Future<void> _resumeWebView() async {
    final controller = _controller;
    if (controller == null || !_mountWebView || widget.routeDetached) {
      return;
    }
    try {
      if (Platform.isAndroid) {
        await controller.resume();
      } else if (Platform.isIOS) {
        await controller.resumeTimers();
      }
    } catch (e) {
      debugPrint('Failed to resume submission WebView: $e');
    }
  }

  void pauseWebViewDuringScroll() {
    if (!widget.enableScrollPerformancePause) {
      return;
    }
    if (!_isPausedForScroll) {
      _isPausedForScroll = true;
      unawaited(_pauseWebView());
    }
    _scrollWebViewResumeTimer?.cancel();
    _scrollWebViewResumeTimer = Timer(_scrollWebViewResumeDelay, () {
      _isPausedForScroll = false;
      unawaited(_resumeWebView());
    });
  }

  Future<SubmissionDescriptionWebViewContent> _processInitialHtml(
      String html) async {
    final content =
        await _submissionDescriptionRepository.processInitialHtml(html);
    _submissionDescriptionHtml = content.html;
    return content;
  }

  /// Fetches and cleans the HTML content for the submission description.
  Future<SubmissionDescriptionWebViewContent> _fetchCleanHTML() async {
    final content = await _submissionDescriptionRepository.fetchContent(
      widget.submissionId,
    );
    _submissionDescriptionHtml = content.html;
    return content;
  }

  /// Searches the provided HTML for a truncated URL and returns the full URL.
  /// Returns the original truncated URL when a better match is not found to
  /// satisfy non-null callbacks passed to `handleFALink`.
  String _getFullLinkFromFetchedHtml(String truncatedUrl,
      {String? htmlSource}) {
    final String? source = htmlSource ?? _submissionDescriptionHtml;
    if (source == null) return truncatedUrl;
    return _submissionDescriptionRepository.findFullLink(
      source,
      truncatedUrl,
    );
  }

  Future<String?> getPlainText() async {
    if (_submissionDescriptionHtml == null) return null;
    return _submissionDescriptionRepository.plainText(
      _submissionDescriptionHtml!,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<SubmissionDescriptionWebViewContent>(
      future: _submissionDescriptionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 300,
            child: Center(
                child: PulsatingLoadingIndicator(
                    size: 58.0, assetPath: 'assets/icons/fathemed.png')),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Failed to load submission description.\n${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }
        final content = snapshot.data;
        final cleanHtml = content?.html ?? '';
        final faThemeCss = content?.faThemeCss ?? '';
        _submissionDescriptionHtml ??= cleanHtml;

        if (!_mountWebView) {
          return ColoredBox(
            color: Colors.black,
            child: SizedBox(
              height: _webViewHeight,
              width: double.infinity,
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final webViewHeight =
                widget.fillAvailableHeight && constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : _webViewHeight;

            return Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
              child: RepaintBoundary(
                child: ExcludeSemantics(
                  child: ColoredBox(
                    color: Colors.black,
                    child: SizedBox(
                      height: webViewHeight,
                      child: InAppWebView(
              gestureRecognizers: widget.enableTextSelection
                  ? <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        () => LongPressGestureRecognizer(),
                      ),
                    }
                  : null,
              initialData: InAppWebViewInitialData(
                data: _submissionDescriptionRepository.buildWebViewHtml(
                  submissionDescriptionHtml: cleanHtml,
                  faThemeCss: faThemeCss,
                  enableTextSelection: widget.enableTextSelection,
                ),
                baseUrl: WebUri('https://www.furaffinity.net'),
                encoding: 'utf-8',
                mimeType: 'text/html',
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: true,
                disableVerticalScroll: false,
                disableHorizontalScroll: false,
                verticalScrollBarEnabled: false,
                horizontalScrollBarEnabled: false,
                supportMultipleWindows: true,
                // useWideViewPort: true,
                // loadWithOverviewMode: true,
                useHybridComposition: widget.forceHybridComposition,
                transparentBackground: Platform.isIOS,
                textZoom: 100,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onCreateWindow: (controller, createWindowReq) async {
                final url = createWindowReq.request.url?.toString() ?? '';
                if (url.isNotEmpty) {
                  await handleFALink(context, url,
                      htmlSource: url, getFullUrl: _getFullLinkFromFetchedHtml);
                }
                return true;
              },
              onLoadStop: (controller, url) async {
                String heightString = await controller.evaluateJavascript(
                  source: faDocumentBodyScrollHeightScript,
                );
                double height = double.tryParse(heightString) ?? 300.0;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (!widget.fillAvailableHeight) {
                    setState(() {
                      _webViewHeight = height;
                    });
                  }
                  if (widget.onHeightChanged != null) {
                    widget.onHeightChanged!(height);
                  }
                });
              },
              onScrollChanged: (controller, x, y) {
                pauseWebViewDuringScroll();
              },
              shouldOverrideUrlLoading: (controller, navAction) async {
                final url = navAction.request.url.toString();
                if (Platform.isAndroid) {
                  if (navAction.isForMainFrame) {
                    await handleFALink(context, url,
                        htmlSource: url,
                        getFullUrl: _getFullLinkFromFetchedHtml);
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                } else if (Platform.isIOS) {
                  if (navAction.navigationType ==
                      NavigationType.LINK_ACTIVATED) {
                    if (url == "https://www.furaffinity.net/") {
                      return NavigationActionPolicy.ALLOW;
                    }
                    await handleFALink(context, url,
                        htmlSource: url,
                        getFullUrl: _getFullLinkFromFetchedHtml);
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                }
                return NavigationActionPolicy.ALLOW;
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame == false) return;
                showAppSnackBar(context,
                    'Failed to load content: ${error.description}',
                    backgroundColor: Colors.red);
              },
              onReceivedHttpError: (controller, request, errorResponse) {
                if (request.isForMainFrame == false) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'HTTP Error ${errorResponse.statusCode}: ${errorResponse.reasonPhrase}',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('WebView Console: ${consoleMessage.message}');
              },
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class SubmissionDescriptionWebViewScreen extends StatelessWidget {
  final String submissionId;
  final String? initialHtml;
  const SubmissionDescriptionWebViewScreen(
      {Key? key, required this.submissionId, this.initialHtml})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final androidBottomInset = Platform.isAndroid
        ? [
            mediaQuery.viewPadding.bottom,
            mediaQuery.padding.bottom,
            mediaQuery.systemGestureInsets.bottom,
          ].reduce((value, element) => value > element ? value : element)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Text'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: androidBottomInset),
        child: SubmissionDescriptionWebView(
          submissionId: submissionId,
          initialHtml: initialHtml,
          forceHybridComposition: true,
          enableTextSelection: true,
          enableScrollPerformancePause: false,
          fillAvailableHeight: true,
        ),
      ),
    );
  }
}
