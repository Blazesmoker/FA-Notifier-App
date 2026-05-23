import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:FANotifier/features/submissions/data/submission_description_parser.dart';
import 'package:FANotifier/features/submissions/data/submission_description_service.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/shared/utils/fa_link_handler.dart';
import 'package:FANotifier/shared/utils/utils.dart';

class SubmissionDescriptionWebView extends StatefulWidget {
  final String submissionId;
  final String? initialHtml;
  final VoidCallback? onDispose;
  final bool forceHybridComposition;
  final bool enableTextSelection;
  final bool enableScrollPerformancePause;
  final void Function(double height)? onHeightChanged;
  final bool routeDetached;

  const SubmissionDescriptionWebView({
    required this.submissionId,
    this.initialHtml,
    this.onDispose,
    this.forceHybridComposition = false,
    this.enableTextSelection = false,
    this.enableScrollPerformancePause = true,
    this.onHeightChanged,
    this.routeDetached = false,
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

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
        accountName: 'flutter_secure_storage_service',
        accessibility: KeychainAccessibility.first_unlock),
  );
  late final SubmissionDescriptionService _submissionDescriptionService =
      SubmissionDescriptionService(secureStorage: _secureStorage);
  late Future<String> _submissionDescriptionFuture;
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

  Future<String> _processInitialHtml(String html) async {
    final descriptionHtml = extractSubmissionDescriptionHtml(
      html,
      allowBodyFallback: true,
    );
    final cleanHtml = _injectFACSS(descriptionHtml);
    _submissionDescriptionHtml = cleanHtml;
    return cleanHtml;
  }

  /// Fetches and cleans the HTML content for the submission description.
  Future<String> _fetchCleanHTML() async {
    final descriptionHtml =
        await _submissionDescriptionService.fetchDescriptionHtml(
      widget.submissionId,
    );
    final cleanHtml = _injectFACSS(descriptionHtml);
    _submissionDescriptionHtml = cleanHtml;
    return cleanHtml;
  }

  /// Injects CSS to enable text selection and apply the FA dark theme.
  String _injectFACSS(String submissionDescHtml) {
    String bgColor =
        '#${background.value.toRadixString(16).substring(2).padLeft(6, '0')}';
    String textColor = '#FFFFFF';

    final selectionCss = widget.enableTextSelection
        ? '''
-webkit-touch-callout: default;
-webkit-user-select: text;
user-select: text;
'''
        : '''
-webkit-touch-callout: none !important;
-webkit-user-select: none !important;
user-select: none !important;
''';

    return '''
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <base href="https://www.furaffinity.net/">

    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Open+Sans:300,300i,400,400i,500,500i,600,600i,700,700i">
    <link rel="stylesheet" href="https://www.furaffinity.net/themes/beta/css/ui_theme_dark.css?u=2024112800">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/wenk/1.0.8/wenk.min.css">

    <style>
      ::selection {
        background: #E09321 !important;
        color: #fff !important;
      }

      ::-webkit-selection {
        background: #E09321 !important;
        color: #fff !important;
      }

      html, body {
        margin: 0 !important;
        padding: 0 !important;
        background-color: #000 !important;
        color: $textColor !important;
        font-family: 'Open Sans', sans-serif;
        $selectionCss
      }

      body {
        margin: 8px;
      }

      .submission-description,
      .bbcode,
      .user-submitted-links {
        background-color: transparent !important;
      }

      img {
        max-width: 100%;
        height: auto;
      }

      a.iconusername img {
        width: 60px;
        height: auto;
      }

      @media (max-width: 600px) {
        a.iconusername img {
          width: 40px;
        }
      }

      @media (min-width: 1200px) {
        a.iconusername img {
          width: 80px;
        }
      }

      code {
        display: block;
        margin-bottom: 10px;
      }

      .bbcode_center {
        text-align: center !important;
      }

      .bbcode_right {
        text-align: right !important;
        display: block;
      }

      .bbcode_left {
        text-align: left !important;
        display: block;
      }

      h1, h2, h3, h4 {
        color: #fff !important;
      }

      h1, h2, h3, h4, h5, h6 {
        text-align: center;
      }

      sup.bbcode_sup {
        display: block;
        text-align: inherit;
        margin-bottom: 10px;
      }

      a {
        color: #E09321 !important;
        text-decoration: none !important;
      }

      a.auto_link.named_url:hover {
        text-decoration: underline;
      }
    </style>

    <script src="https://www.furaffinity.net/themes/beta/js/prototype.1.7.3.min.js"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/common.js?u=2024112800"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/script.js?u=2024112800"></script>
  </head>
  <body class="ui_theme_dark">
    $submissionDescHtml
  </body>
</html>
''';
  }

  /// Searches the provided HTML for a truncated URL and returns the full URL.
  /// Returns the original truncated URL when a better match is not found to
  /// satisfy non-null callbacks passed to `handleFALink`.
  String _getFullLinkFromFetchedHtml(String truncatedUrl,
      {String? htmlSource}) {
    final String? source = htmlSource ?? _submissionDescriptionHtml;
    if (source == null) return truncatedUrl;
    return findFullSubmissionAutoShortenedLink(source, truncatedUrl);
  }

  Future<String?> getPlainText() async {
    if (_submissionDescriptionHtml == null) return null;
    return plainTextFromSubmissionHtml(_submissionDescriptionHtml!);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<String>(
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
        final cleanHtml = snapshot.data ?? '';
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

        return Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
          child: RepaintBoundary(
            child: ExcludeSemantics(
              child: ColoredBox(
                color: Colors.black,
                child: SizedBox(
                  height: _webViewHeight,
                  child: InAppWebView(
              initialData: InAppWebViewInitialData(
                data: _injectFACSS(cleanHtml),
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
                  source: "document.body.scrollHeight.toString()",
                );
                double height = double.tryParse(heightString) ?? 300.0;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _webViewHeight = height;
                  });
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
              onLoadError: (controller, url, code, message) {
                showAppSnackBar(context, 'Failed to load content: $message',
                    backgroundColor: Colors.red);
              },
              onLoadHttpError: (controller, url, statusCode, description) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('HTTP Error $statusCode: $description'),
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
        ),
      ),
    );
  }
}
