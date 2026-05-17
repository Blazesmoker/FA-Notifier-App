import 'dart:async';
import 'dart:io';

import 'package:FANotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:FANotifier/features/profile/data/user_description_parser.dart';
import 'package:FANotifier/features/profile/data/user_description_service.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/journals/presentation/openjournal.dart';
import 'package:FANotifier/features/submissions/presentation/openpost.dart';
import 'package:FANotifier/features/profile/domain/profile_section.dart';

enum UserDescriptionWebViewPauseReason { route, visibility, scrolling }

class UserDescriptionWebView extends StatefulWidget {
  final String sanitizedUsername;
  final String? initialHtml;
  final VoidCallback? onDispose;
  final bool forceHybridComposition;
  final bool enableTextSelection;
  final bool enableScrollPerformancePause;
  final bool disableIosScrolling;
  final ValueChanged<bool>? onWebViewLoaded;

  const UserDescriptionWebView({
    Key? key,
    required this.sanitizedUsername,
    this.initialHtml,
    this.onDispose,
    this.enableTextSelection = false,
    this.enableScrollPerformancePause = true,
    this.disableIosScrolling = false,
    this.forceHybridComposition = false,
    this.onWebViewLoaded,
  }) : super(key: key);

  @override
  UserDescriptionWebViewState createState() => UserDescriptionWebViewState();
}

class UserDescriptionWebViewState extends State<UserDescriptionWebView>
    with AutomaticKeepAliveClientMixin<UserDescriptionWebView> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
        accountName: 'flutter_secure_storage_service',
        accessibility: KeychainAccessibility.first_unlock),
  );
  late final UserDescriptionService _userDescriptionService =
      UserDescriptionService(secureStorage: _secureStorage);
  late Future<String> _userDescriptionFuture;
  InAppWebViewController? _controller;
  final Set<UserDescriptionWebViewPauseReason> _pauseReasons =
      <UserDescriptionWebViewPauseReason>{};
  static const Duration _scrollWebViewResumeDelay =
      Duration(milliseconds: 50);
  Timer? _scrollWebViewResumeTimer;
  bool _isPausedForScroll = false;
  double _webViewHeight = 50.0;
  bool _mountWebView = true;
  bool _webViewLoaded = false;

  // Store the cleaned HTML so we search it for full links.
  String? _userDescriptionHtml;

  @override
  void initState() {
    super.initState();
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

  Future<void> pauseWebView({
    UserDescriptionWebViewPauseReason reason =
        UserDescriptionWebViewPauseReason.route,
  }) async {
    if (!_pauseReasons.add(reason)) {
      return;
    }
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
    final controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      if (Platform.isAndroid) {
        await controller.pause();
      }
    } catch (e) {
      debugPrint('Failed to pause profile WebView: $e');
    }
  }

  Future<void> resumeWebView({
    UserDescriptionWebViewPauseReason reason =
        UserDescriptionWebViewPauseReason.route,
  }) async {
    if (!_pauseReasons.remove(reason)) {
      return;
    }
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
    final controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      if (Platform.isAndroid) {
        await controller.resume();
      }
    } catch (e) {
      debugPrint('Failed to resume profile WebView: $e');
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

  Future<String> _processInitialHtml(String html) async {
    final extractedHtml = extractUserDescriptionHtml(
      html,
      allowBodyFallback: true,
    );
    _userDescriptionHtml = extractedHtml;
    return extractedHtml;
  }

  /// Fetches and cleans the HTML content for the user description.
  Future<String> _fetchCleanHTML() async {
    final extractedHtml = await _userDescriptionService.fetchCleanHtml(
      widget.sanitizedUsername,
    );
    _userDescriptionHtml = extractedHtml;
    return extractedHtml;
  }

  /// Injects necessary CSS into the HTML content.
  String _injectFACSS(String userDescHtml) {
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
        color: #fff !important;
        font-family: 'Open Sans', sans-serif;
        $selectionCss
      }

      body {
        margin: 8px;
      }

      .container, .section-body, .userpage-layout-profile, .user-submitted-links {
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
        margin: 10px 0;
      }

      .bbcode_center {
        text-align: center !important;
      }

      .bbcode_right {
        text-align: right !important;
      }

      .bbcode_left {
        text-align: left !important;
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
    </style>
    <script src="https://www.furaffinity.net/themes/beta/js/prototype.1.7.3.min.js"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/common.js?u=2024112800"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/script.js?u=2024112800"></script>
  </head>
  <body class="ui_theme_dark">
    $userDescHtml
  </body>
</html>
''';
  }

  /// Searches the given [htmlSource] for an <a> tag with class "auto_link_shortened"
  /// whose inner text equals [truncatedUrl]. If found, returns the full URL from its
  /// title attribute (or from its href if title is missing). If no match is found, returns null.
  /// If [htmlSource] is not provided, it falls back to using the stored _userDescriptionHtml.
  String? _getFullLinkFromFetchedHtml(String truncatedUrl,
      {String? htmlSource}) {
    final String? source = htmlSource ?? _userDescriptionHtml;
    if (source == null) return null;
    return findFullAutoShortenedLink(source, truncatedUrl);
  }

  /// Returns plain text by stripping HTML tags from the cleaned HTML.
  Future<String?> getPlainText() async {
    if (_userDescriptionHtml == null) return null;
    return plainTextFromHtml(_userDescriptionHtml!);
  }

  /// Processes a FurAffinity URL.
  /// It handles gallery folder links, user links, journal links, and submission/view links.
  /// If no match is found, it opens the URL externally.
  Future<void> _handleFALink(BuildContext context, String url,
      {String? htmlSource}) async {
    String fullUrlToMatch = url;
    // If the URL appears truncated (contains "....."), tries to recover the full URL.
    if (url.contains('.....')) {
      final recoveredLink =
          _getFullLinkFromFetchedHtml(url, htmlSource: htmlSource);
      if (recoveredLink != null) {
        fullUrlToMatch = recoveredLink;
        debugPrint("Recovered full URL: $fullUrlToMatch");
      }
    }

    final Uri uri = Uri.parse(fullUrlToMatch);
    final String urlToMatch = uri.toString();

    // 1. Gallery Folder Link
    final RegExp galleryFolderRegex = RegExp(
      r'^https?://(?:www\.)?furaffinity\.net/gallery/([a-zA-Z0-9\-_.~]+)/folder/(\d+)/([a-zA-Z0-9\-_.~]+)/?$',
    );
    if (galleryFolderRegex.hasMatch(urlToMatch)) {
      final match = galleryFolderRegex.firstMatch(urlToMatch)!;
      final String tappedUsername = match.group(1)!;
      final String folderNumber = match.group(2)!;
      final String folderName = match.group(3)!;
      final String folderUrl =
          'https://www.furaffinity.net/gallery/$tappedUsername/folder/$folderNumber/$folderName/';

      Navigator.push(
        context,
        UserProfileScreen.route(
          nickname: tappedUsername,
          initialSection: ProfileSection.Gallery,
          initialFolderUrl: folderUrl,
          initialFolderName: folderName,
        ),
      );
      return;
    }

    // 2. User Link
    final RegExp userRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([a-zA-Z0-9\-_.~]+)/?$',
    );
    if (userRegex.hasMatch(urlToMatch)) {
      final String tappedUsername = userRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        UserProfileScreen.route(nickname: tappedUsername),
      );
      return;
    }

    // 3. Journal Link
    final RegExp journalRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/(?:journals/([a-zA-Z0-9\-_.~]+)|journal/(\d+))(?:/.*)?(?:#.*)?$',
    );

    if (journalRegex.hasMatch(urlToMatch)) {
      final Match match = journalRegex.firstMatch(urlToMatch)!;
      final String? username = match.group(1);
      final String? journalId = match.group(2);

      if (username != null) {
        // Matched: /journals/username/
        Navigator.push(
          context,
          UserProfileScreen.route(
            nickname: username,
            initialSection: ProfileSection.Journals,
          ),
        );
      } else if (journalId != null) {
        // Matched: /journal/12345/
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OpenJournal(uniqueNumber: journalId),
          ),
        );
      }

      return;
    }

    // 4. Submission/View Link
    final RegExp viewRegex = RegExp(
      r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$',
    );
    if (viewRegex.hasMatch(urlToMatch)) {
      final String submissionId = viewRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        OpenPost.route(
          uniqueNumber: submissionId,
          imageUrl: '',
        ),
      );
      return;
    }

    // 5. Fallback: open externally
    await launchUrlString(fullUrlToMatch, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<String>(
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

        final cleanHtml = snapshot.data ?? '';

        _userDescriptionHtml ??= cleanHtml;

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
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      if (Platform.isAndroid && _pauseReasons.isNotEmpty) {
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
                      String heightString =
                          await controller.evaluateJavascript(
                        source: "document.body.scrollHeight.toString()",
                      );
                      double height = double.tryParse(heightString) ?? 300.0;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _webViewHeight = height;
                          _webViewLoaded = true;
                        });
                        widget.onWebViewLoaded?.call(true);
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
                    onLoadError: (controller, url, code, message) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to load content: $message'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    },
                    onLoadHttpError:
                        (controller, url, statusCode, description) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('HTTP Error $statusCode: $description'),
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

class UserDescriptionWebViewScreen extends StatelessWidget {
  final String sanitizedUsername;
  final String? initialHtml;
  const UserDescriptionWebViewScreen(
      {Key? key, required this.sanitizedUsername, this.initialHtml})
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
        ),
      ),
    );
  }
}
