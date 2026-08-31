import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/profile/domain/user_description_repository.dart';
import 'package:fanotifier/features/profile/domain/user_description_webview_content.dart';
import 'package:fanotifier/shared/fa/fa_webview_document_scripts.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

enum UserDescriptionWebViewPauseReason { route, tab, visibility, scrolling }

class UserDescriptionWebView extends StatefulWidget {
  final String sanitizedUsername;
  final String? initialHtml;
  final VoidCallback? onDispose;
  final bool forceHybridComposition;
  final bool enableTextSelection;
  final bool enableScrollPerformancePause;
  final bool disableIosScrolling;
  final bool fillAvailableHeight;
  final bool gifPlaybackEnabled;
  final ValueChanged<bool>? onWebViewLoaded;

  const UserDescriptionWebView({
    super.key,
    required this.sanitizedUsername,
    this.initialHtml,
    this.onDispose,
    this.enableTextSelection = false,
    this.enableScrollPerformancePause = true,
    this.disableIosScrolling = false,
    this.fillAvailableHeight = false,
    this.gifPlaybackEnabled = true,
    this.forceHybridComposition = false,
    this.onWebViewLoaded,
  });

  @override
  UserDescriptionWebViewState createState() => UserDescriptionWebViewState();
}

class UserDescriptionWebViewState extends State<UserDescriptionWebView>
    with AutomaticKeepAliveClientMixin<UserDescriptionWebView> {
  late final UserDescriptionRepository _userDescriptionRepository;
  late Future<UserDescriptionWebViewContent> _userDescriptionFuture;
  InAppWebViewController? _controller;
  final Set<UserDescriptionWebViewPauseReason> _pauseReasons =
      <UserDescriptionWebViewPauseReason>{};
  final Set<UserDescriptionWebViewPauseReason> _gifPauseReasons =
      <UserDescriptionWebViewPauseReason>{};
  Future<void> _gifPlaybackUpdate = Future<void>.value();
  static const Duration _scrollWebViewResumeDelay =
      Duration(milliseconds: 50);
  Timer? _scrollWebViewResumeTimer;
  bool _isPausedForScroll = false;
  double _webViewHeight = 50.0;
  bool _mountWebView = true;
  bool _didReportLoaded = false;

  // Store the cleaned HTML so we search it for full links.
  String? _userDescriptionHtml;

  @override
  void initState() {
    super.initState();
    _userDescriptionRepository = context.read<UserDescriptionRepository>();
    if (!widget.gifPlaybackEnabled) {
      _gifPauseReasons.add(UserDescriptionWebViewPauseReason.tab);
    }
    if (widget.initialHtml != null) {
      _userDescriptionFuture = _processInitialHtml(widget.initialHtml!);
    } else {
      _userDescriptionFuture = _fetchCleanHTML();
    }
  }

  @override
  void dispose() {
    _scrollWebViewResumeTimer?.cancel();
    _controller = null;
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant UserDescriptionWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gifPlaybackEnabled != widget.gifPlaybackEnabled) {
      if (widget.gifPlaybackEnabled) {
        unawaited(
          resumeGifPlayback(reason: UserDescriptionWebViewPauseReason.tab),
        );
      } else {
        unawaited(
          pauseGifPlayback(reason: UserDescriptionWebViewPauseReason.tab),
        );
      }
    }
  }

  Future<void> pauseGifPlayback({
    UserDescriptionWebViewPauseReason reason =
        UserDescriptionWebViewPauseReason.visibility,
  }) {
    if (!_gifPauseReasons.add(reason)) {
      return Future<void>.value();
    }
    return _queueGifPlaybackUpdate();
  }

  Future<void> resumeGifPlayback({
    UserDescriptionWebViewPauseReason reason =
        UserDescriptionWebViewPauseReason.visibility,
  }) {
    if (!_gifPauseReasons.remove(reason)) {
      return Future<void>.value();
    }
    return _queueGifPlaybackUpdate();
  }

  Future<void> _queueGifPlaybackUpdate() {
    _gifPlaybackUpdate = _gifPlaybackUpdate.then((_) async {
      final controller = _controller;
      if (controller == null) {
        return;
      }
      final enabled = _gifPauseReasons.isEmpty;
      if (Platform.isAndroid) {
        if (enabled) {
          await controller.resume();
        } else {
          await controller.pause();
        }
      } else {
        await controller.evaluateJavascript(
          source: 'window.__faProfileSetGifPlayback?.call(null, $enabled);',
        );
      }
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint('Failed to update profile GIF playback: $error');
    });
    return _gifPlaybackUpdate;
  }

  Future<void> pauseWebView({
    UserDescriptionWebViewPauseReason reason =
        UserDescriptionWebViewPauseReason.route,
  }) async {
    if (!_pauseReasons.add(reason)) {
      return;
    }
    await pauseGifPlayback(reason: reason);
    if (_pauseReasons.contains(UserDescriptionWebViewPauseReason.route)) {
      if (!mounted) {
        _mountWebView = false;
        _controller = null;
        return;
      }
      if (_mountWebView) {
        setState(() {
          _mountWebView = false;
        });
      }
      _controller = null;
      return;
    }
  }

  Future<void> resumeWebView({
    UserDescriptionWebViewPauseReason reason =
        UserDescriptionWebViewPauseReason.route,
  }) async {
    if (!_pauseReasons.remove(reason)) {
      return;
    }
    await resumeGifPlayback(reason: reason);
    final shouldMount =
        !_pauseReasons.contains(UserDescriptionWebViewPauseReason.route);
    if (!shouldMount) {
      return;
    }
    if (!_mountWebView) {
      if (!mounted) {
        _mountWebView = true;
        return;
      }
      setState(() {
        _mountWebView = true;
      });
      return;
    }
    if (_pauseReasons.contains(UserDescriptionWebViewPauseReason.visibility) ||
        _pauseReasons.contains(UserDescriptionWebViewPauseReason.scrolling)) {
      return;
    }
  }

  void _pauseWebViewDuringScroll() {
    if (!widget.enableScrollPerformancePause) {
      return;
    }
    if (!_isPausedForScroll) {
      _isPausedForScroll = true;
      unawaited(
        pauseWebView(
          reason: UserDescriptionWebViewPauseReason.scrolling,
        ),
      );
    }
    _scrollWebViewResumeTimer?.cancel();
    _scrollWebViewResumeTimer = Timer(_scrollWebViewResumeDelay, () {
      _isPausedForScroll = false;
      unawaited(
        resumeWebView(
          reason: UserDescriptionWebViewPauseReason.scrolling,
        ),
      );
    });
  }

  Future<UserDescriptionWebViewContent> _processInitialHtml(String html) async {
    final extractedHtml =
        await _userDescriptionRepository.extractInitialHtml(html);
    final htmlWithInlinedIcons =
        await _userDescriptionRepository.inlineIcons(extractedHtml);
    _userDescriptionHtml = htmlWithInlinedIcons;
    return _userDescriptionRepository.buildWebViewContent(
      htmlWithInlinedIcons,
    );
  }

  /// Fetches and cleans the HTML content for the user description.
  Future<UserDescriptionWebViewContent> _fetchCleanHTML() async {
    final extractedHtml = await _userDescriptionRepository.fetchCleanHtml(
      widget.sanitizedUsername,
    );
    final htmlWithInlinedIcons =
        await _userDescriptionRepository.inlineIcons(extractedHtml);
    _userDescriptionHtml = htmlWithInlinedIcons;
    return _userDescriptionRepository.buildWebViewContent(
      htmlWithInlinedIcons,
    );
  }

  /// Searches the given [htmlSource] for an <a> tag with class "auto_link_shortened"
  /// whose inner text equals [truncatedUrl]. If found, returns the full URL from its
  /// title attribute (or from its href if title is missing). If no match is found, returns the original URL.
  /// If [htmlSource] is not provided, it falls back to using the stored _userDescriptionHtml.
  String _getFullLinkFromFetchedHtml(String truncatedUrl,
      {String? htmlSource}) {
    final String? source = htmlSource ?? _userDescriptionHtml;
    if (source == null) return truncatedUrl;
    return _userDescriptionRepository.findFullLink(source, truncatedUrl);
  }

  /// Returns plain text by stripping HTML tags from the cleaned HTML.
  Future<String?> getPlainText() async {
    if (_userDescriptionHtml == null) return null;
    return _userDescriptionRepository.plainText(_userDescriptionHtml!);
  }

  /// Processes a FurAffinity URL.
  /// It handles gallery folder links, user links, journal links, and submission/view links.
  /// If no match is found, it opens the URL externally.
  Future<void> _handleFALink(BuildContext context, String url,
      {String? htmlSource}) async {
    await handleFALink(
      context,
      url,
      htmlSource: htmlSource,
      getFullUrl: _getFullLinkFromFetchedHtml,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<UserDescriptionWebViewContent>(
      future: _userDescriptionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 600,
            child: Center(
              child: PulsatingLoadingIndicator(
                size: 68.0,
                assetPath: 'assets/icons/fathemed.png',
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Failed to load user description.\n${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        final content = snapshot.data;
        final cleanHtml = content?.html ?? '';
        final faThemeCss = content?.faThemeCss ?? '';

        _userDescriptionHtml ??= cleanHtml;

        if (!_mountWebView) {
          return Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
            child: ColoredBox(
              color: Colors.black,
              child: SizedBox(
                height: _webViewHeight,
                width: double.infinity,
              ),
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
                      data: _userDescriptionRepository.buildWebViewHtml(
                        userDescriptionHtml: cleanHtml,
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
                      disableVerticalScroll:
                          widget.disableIosScrolling && Platform.isIOS,
                      disableHorizontalScroll:
                          widget.disableIosScrolling && Platform.isIOS,
                      verticalScrollBarEnabled: false,
                      horizontalScrollBarEnabled: false,
                      supportMultipleWindows: true,
                      useHybridComposition: widget.forceHybridComposition,
                      transparentBackground: Platform.isIOS,
                      disallowOverScroll: Platform.isIOS,
                      textZoom: 100,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      if (Platform.isAndroid &&
                          (_pauseReasons.isNotEmpty ||
                              _gifPauseReasons.isNotEmpty)) {
                        controller.pause();
                      }
                    },
                    onCreateWindow: (controller, createWindowReq) async {
                      final url =
                          createWindowReq.request.url?.toString() ?? '';
                      if (url.isNotEmpty) {
                        await _handleFALink(context, url);
                      }
                      return true;
                    },
                    onLoadStop: (controller, url) async {
                      await _queueGifPlaybackUpdate();
                      String heightString =
                          await controller.evaluateJavascript(
                        source: faDocumentBodyScrollHeightScript,
                      );
                      double height = double.tryParse(heightString) ?? 300.0;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        if (!widget.fillAvailableHeight &&
                            (_webViewHeight - height).abs() > 0.1) {
                          setState(() {
                            _webViewHeight = height;
                          });
                        }
                        if (!_didReportLoaded) {
                          _didReportLoaded = true;
                          widget.onWebViewLoaded?.call(true);
                        }
                      });
                    },
                    onScrollChanged: (controller, x, y) {
                      _pauseWebViewDuringScroll();
                    },
                    shouldOverrideUrlLoading: (controller, navAction) async {
                      final url = navAction.request.url.toString();

                      if (Platform.isAndroid) {
                        if (navAction.isForMainFrame) {
                          await _handleFALink(context, url);
                          return NavigationActionPolicy.CANCEL;
                        }
                        return NavigationActionPolicy.ALLOW;
                      } else if (Platform.isIOS) {
                        if (navAction.navigationType ==
                            NavigationType.LINK_ACTIVATED) {
                          if (url == "https://www.furaffinity.net/") {
                            return NavigationActionPolicy.ALLOW;
                          }
                          await _handleFALink(context, url);
                          return NavigationActionPolicy.CANCEL;
                        }
                        return NavigationActionPolicy.ALLOW;
                      }
                      return NavigationActionPolicy.ALLOW;
                    },
                    onReceivedError: (controller, request, error) {
                      if (request.isForMainFrame == false) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to load content: ${error.description}',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    },
                    onReceivedHttpError:
                        (controller, request, errorResponse) {
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

class UserDescriptionWebViewScreen extends StatelessWidget {
  final String sanitizedUsername;
  final String? initialHtml;
  const UserDescriptionWebViewScreen(
      {super.key, required this.sanitizedUsername, this.initialHtml})
      ;

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
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: androidBottomInset),
        child: UserDescriptionWebView(
          sanitizedUsername: sanitizedUsername,
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
