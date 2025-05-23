import 'dart:convert';
import 'dart:io';

import 'package:FANotifier/screens/user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'openjournal.dart';
import 'openpost.dart';

class UserDescriptionWebView extends StatefulWidget {
  final String sanitizedUsername;
  final VoidCallback? onDispose;
  final bool forceHybridComposition;
  final ValueChanged<bool>? onWebViewLoaded;

  const UserDescriptionWebView({
    Key? key,
    required this.sanitizedUsername,
    this.onDispose,
    this.forceHybridComposition = false,
    this.onWebViewLoaded,
  }) : super(key: key);

  @override
  UserDescriptionWebViewState createState() => UserDescriptionWebViewState();
}

class UserDescriptionWebViewState extends State<UserDescriptionWebView>
    with AutomaticKeepAliveClientMixin<UserDescriptionWebView> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late Future<String> _userDescriptionFuture;
  double _webViewHeight = 50.0;
  bool _isWebViewVisible = true;
  bool _webViewLoaded = false;

  // Store the cleaned HTML so we search it for full links.
  String? _userDescriptionHtml;

  @override
  void initState() {
    super.initState();
    _userDescriptionFuture = _fetchCleanHTML();
  }

  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  void hideWebView() {
    setState(() {
      _isWebViewVisible = false;
    });
  }

  /// Fetches and cleans the HTML content for the user description.
  Future<String> _fetchCleanHTML() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('User not logged in or missing cookies.');
    }

    final url = 'https://www.furaffinity.net/user/${widget.sanitizedUsername}/';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch user page: ${response.statusCode}');
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    final doc = html_parser.parse(decodedBody);

    // Remove unwanted elements
    doc.querySelectorAll(
      'script, .footerAds, #ddmenu, .mobile-navigation, '
          '.mobile-notification-bar, #header, .userpage-layout-left-col, '
          '.userpage-layout-right-col, #footer, .online-stats, .news-block',
    ).forEach((e) => e.remove());


    final userDescElem = doc.querySelector('section.userpage-layout-profile')
        ?? doc.querySelector('td.ldot');

    if (userDescElem == null) {
      return '<p>No user profile found.</p>';
    }

    String extractedHtml;
    if (userDescElem.localName == 'section') {
      // Modern markup: use the entire section element.
      extractedHtml = userDescElem.outerHtml.trim();
    } else if (userDescElem.localName == 'td') {
      // Classic markup: remove the header portion (User Title, Registered Since, etc.)
      String classicHtml = userDescElem.innerHtml;
      const headerMarker = '<b>Artist Profile:</b><br>';
      final splitIndex = classicHtml.indexOf(headerMarker);
      if (splitIndex != -1) {
        extractedHtml = classicHtml.substring(splitIndex + headerMarker.length).trim();
      } else {
        extractedHtml = classicHtml.trim();
      }
    } else {
      extractedHtml = userDescElem.outerHtml.trim();
    }

    final cleanHtml = _injectFACSS(extractedHtml);
    // Save it for link processing.
    _userDescriptionHtml = cleanHtml;
    return cleanHtml;
  }

  /// Injects necessary CSS into the HTML content.
  String _injectFACSS(String userDescHtml) {
    return '''
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <base href="https://www.furaffinity.net/">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Open+Sans:300,300i,400,400i,500,500i,600,600i,700,700i">
    <link rel="stylesheet" href="https://www.furaffinity.net/themes/beta/css/ui_theme_dark.css?u=2024112800">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/wenk/1.0.8/wenk.min.css">
    <style>
      /* Custom selection styling */
      ::selection {
        background: #E09321 !important;
        color: #fff !important;
      }
      ::-webkit-selection {
        background: #E09321 !important;
        color: #fff !important;
      }
      
      /* Ensure touch callout is enabled */
      body {
        -webkit-touch-callout: default;
      }

      /* Force black background and allow text selection */
      html, body {
        margin: 0 !important;
        padding: 0 !important;
        background-color: #000 !important;
        color: #fff !important;
        font-family: 'Open Sans', sans-serif;
        -webkit-user-select: text;
        user-select: text;
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
      h1, h2, h3, h4, h5, h6 {
        text-align: center;
      }
      sup.bbcode_sup {
        display: block;
        text-align: inherit;
        margin-bottom: 10px;
      }
      /* Override FA's link styling with your desired color */
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
  String? _getFullLinkFromFetchedHtml(String truncatedUrl, {String? htmlSource}) {
    final String? source = htmlSource ?? _userDescriptionHtml;
    if (source == null) return null;

    final document = html_parser.parse(source);
    for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
      if (anchor.text.trim() == truncatedUrl) {
        return anchor.attributes['title'] ?? anchor.attributes['href'];
      }
    }
    return null;
  }

  /// Returns plain text by stripping HTML tags from the cleaned HTML.
  Future<String?> getPlainText() async {
    if (_userDescriptionHtml == null) return null;
    // Parse the HTML and return only the text content.
    final document = html_parser.parse(_userDescriptionHtml!);
    return document.body?.text.trim();
  }

  /// Processes a FurAffinity URL.
  ///
  /// It handles gallery folder links, user links, journal links, and submission/view links.
  /// If no match is found, it opens the URL externally.
  Future<void> _handleFALink(BuildContext context, String url, {String? htmlSource}) async {
    String fullUrlToMatch = url;
    // If the URL appears truncated (contains "....."), tries to recover the full URL.
    if (url.contains('.....')) {
      final recoveredLink = _getFullLinkFromFetchedHtml(url, htmlSource: htmlSource);
      if (recoveredLink != null) {
        fullUrlToMatch = recoveredLink;
        print("Recovered full URL: $fullUrlToMatch");
      }
    }

    final Uri uri = Uri.parse(fullUrlToMatch);
    final String urlToMatch = uri.toString();

    // --- 1. Gallery Folder Link ---
    final RegExp galleryFolderRegex = RegExp(
        r'^https?://(?:www\.)?furaffinity\.net/gallery/([^/]+)/folder/(\d+)/([^/]+)/?$'
    );
    if (galleryFolderRegex.hasMatch(urlToMatch)) {
      final match = galleryFolderRegex.firstMatch(urlToMatch)!;
      final String tappedUsername = match.group(1)!;
      final String folderNumber = match.group(2)!;
      final String folderName = match.group(3)!;
      final String folderUrl = 'https://www.furaffinity.net/gallery/$tappedUsername/folder/$folderNumber/$folderName/';

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            nickname: tappedUsername,
            initialSection: ProfileSection.Gallery,
            initialFolderUrl: folderUrl,
            initialFolderName: folderName,
          ),
        ),
      );
      return;
    }

    // --- 2. User Link ---
    final RegExp userRegex = RegExp(
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([^/]+)/?$'
    );
    if (userRegex.hasMatch(urlToMatch)) {
      final String tappedUsername = userRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(nickname: tappedUsername),
        ),
      );
      return;
    }

    // --- 3. Journal Link ---
    final RegExp journalRegex = RegExp(
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/journal/(\d+)/.*$'
    );
    if (journalRegex.hasMatch(urlToMatch)) {
      final String journalId = journalRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenJournal(uniqueNumber: journalId),
        ),
      );
      return;
    }

    // --- 4. Submission/View Link ---
    final RegExp viewRegex = RegExp(
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$'
    );
    if (viewRegex.hasMatch(urlToMatch)) {
      final String submissionId = viewRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenPost(
            uniqueNumber: submissionId,
            imageUrl: '',
          ),
        ),
      );
      return;
    }

    // --- 5. Fallback: open externally ---
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

        if (!_isWebViewVisible) {
          return const SizedBox.shrink();
        }

        return SizedBox(
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
              useHybridComposition: widget.forceHybridComposition,
            ),
            onCreateWindow: (controller, createWindowReq) async {
              final url = createWindowReq.request.url?.toString() ?? '';
              if (url.isNotEmpty) {
                await _handleFALink(context, url);
              }
              return true;
            },
            onLoadStop: (controller, url) async {

              String heightString = await controller.evaluateJavascript(
                source: "document.body.scrollHeight.toString()",
              );
              double height = double.tryParse(heightString) ?? 300.0;
              Future.delayed(const Duration(milliseconds: 30), () {
                setState(() {
                  _webViewHeight = height;
                  _webViewLoaded = true;
                });

                widget.onWebViewLoaded?.call(true);
              });
            },
            /*

            shouldOverrideUrlLoading: (controller, navAction) async {
              if (navAction.isForMainFrame) {
                final url = navAction.request.url.toString();
                await _handleFALink(context, url);
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },

             */
            shouldOverrideUrlLoading: (controller, navAction) async {
              final url = navAction.request.url.toString();

              if (Platform.isAndroid) {
                // Android logic
                if (navAction.isForMainFrame) {
                  await _handleFALink(context, url);
                  return NavigationActionPolicy.CANCEL; // stop WebView
                }
                return NavigationActionPolicy.ALLOW;
              } else if (Platform.isIOS) {
                // iOS logic
                if (navAction.navigationType == NavigationType.LINK_ACTIVATED) {
                  if (url == "https://www.furaffinity.net/") {
                    return NavigationActionPolicy.ALLOW;
                  }
                  await _handleFALink(context, url);
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              }
              // Default fallback
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
        );
      },
    );
  }
}

class UserDescriptionWebViewScreen extends StatelessWidget {
  final String sanitizedUsername;
  const UserDescriptionWebViewScreen({Key? key, required this.sanitizedUsername})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
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
      body: UserDescriptionWebView(
        sanitizedUsername: sanitizedUsername,
        forceHybridComposition: true,
      ),
    );
  }
}

