import 'dart:convert';
import 'dart:io';

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
import 'user_profile_screen.dart';

class SubmissionDescriptionWebView extends StatefulWidget {
  final String submissionId;
  final VoidCallback? onDispose;
  final bool forceHybridComposition;
  final void Function(double height)? onHeightChanged;

  const SubmissionDescriptionWebView({
    required this.submissionId,
    this.onDispose,
    this.forceHybridComposition = false,
    this.onHeightChanged,
    Key? key,
  }) : super(key: key);

  @override
  SubmissionDescriptionWebViewState createState() =>
      SubmissionDescriptionWebViewState();
}

class SubmissionDescriptionWebViewState extends State<SubmissionDescriptionWebView>
    with AutomaticKeepAliveClientMixin<SubmissionDescriptionWebView> {
  static const Color background = Color(0xFF121212);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late Future<String> _submissionDescriptionFuture;
  double _webViewHeight = 50.0;



  String? _submissionDescriptionHtml;

  @override
  void initState() {
    super.initState();
    _submissionDescriptionFuture = _fetchCleanHTML();
  }

  @override
  void dispose() {
    if (widget.onDispose != null) {
      widget.onDispose!();
    }
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  /// Fetches and cleans the HTML content for the submission description.
  Future<String> _fetchCleanHTML() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      throw Exception('User not logged in or missing cookies.');
    }

    final url = 'https://www.furaffinity.net/view/${widget.submissionId}/';
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch submission page: ${response.statusCode}');
    }

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    final doc = html_parser.parse(decodedBody);

    // Remove unwanted elements
    doc.querySelectorAll(
      'script, .footerAds, #ddmenu, .mobile-navigation, '
          '.mobile-notification-bar, #header, .online-stats, .news-block, '
          '.submission-sidebar, .leaderboardAd, .footerAds, .online-stats',
    ).forEach((e) => e.remove());

    final submissionDesc = doc.querySelector(
        '.submission-description, '
            'td.alt1[width="70%"][valign="top"][align="left"][style*="padding:8px"]'
    );

    if (submissionDesc == null) {
      // Fallback if not found.
      return '<p>No submission description found.</p>';
    }

    // Inject CSS
    final cleanHtml = _injectFACSS(submissionDesc.outerHtml);
    _submissionDescriptionHtml = cleanHtml;
    return cleanHtml;
  }

  /// Injects CSS to enable text selection and apply the FA dark theme.
  String _injectFACSS(String submissionDescHtml) {

    String bgColor =
        '#${background.value.toRadixString(16).substring(2).padLeft(6, '0')}';
    String textColor = '#FFFFFF';

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

        /* Set background, text colors, and allow text selection */
        html, body {
          margin: 0 !important;
          padding: 0 !important;
          background-color: #000 !important;
          color: $textColor !important;
          font-family: 'Open Sans', sans-serif;
          -webkit-user-select: text;
          user-select: text;
        }
        body {
          margin: 8px;
        }
        .submission-description, .bbcode, .user-submitted-links {
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
  String? _getFullLinkFromFetchedHtml(String truncatedUrl, {String? htmlSource}) {
    final String? source = htmlSource ?? _submissionDescriptionHtml;
    if (source == null) return null;

    final document = html_parser.parse(source);
    for (var anchor in document.querySelectorAll('a.auto_link_shortened')) {
      if (anchor.text.trim() == truncatedUrl) {
        return anchor.attributes['title'] ?? anchor.attributes['href'];
      }
    }
    return null;
  }


  Future<void> _handleFALink(BuildContext context, String url, {String? htmlSource}) async {
    String fullUrlToMatch = url;
    if (url.contains('.....')) {
      final recoveredLink = _getFullLinkFromFetchedHtml(url, htmlSource: htmlSource);
      if (recoveredLink != null) {
        fullUrlToMatch = recoveredLink;
        print("Recovered full URL: $fullUrlToMatch");
      }
    }

    final Uri uri = Uri.parse(fullUrlToMatch);
    final String urlToMatch = uri.toString();

    final RegExp galleryFolderRegex = RegExp(
        r'^https?://(?:www\.)?furaffinity\.net/gallery/([^/]+)/folder/(\d+)/([^/]+)/?$'
    );
    if (galleryFolderRegex.hasMatch(urlToMatch)) {
      final match = galleryFolderRegex.firstMatch(urlToMatch)!;
      final String tappedUsername = match.group(1)!;
      final String folderNumber = match.group(2)!;
      final String folderName = match.group(3)!;
      final String folderUrl = 'https://www.furaffinity.net/gallery/$tappedUsername/folder/$folderNumber/$folderName/';
      print('Tapped username: $tappedUsername');
      print('Folder number: $folderNumber');
      print('Folder name: $folderName');
      print('Folder URL: $folderUrl');
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

    await launchUrlString(fullUrlToMatch, mode: LaunchMode.externalApplication);
  }


  Future<String?> getPlainText() async {
    if (_submissionDescriptionHtml == null) return null;
    final document = html_parser.parse(_submissionDescriptionHtml!);
    return document.body?.text.trim();
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
            child: Center(child: PulsatingLoadingIndicator(size: 58.0, assetPath: 'assets/icons/fathemed.png')),
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
              // useWideViewPort: true,
              // loadWithOverviewMode: true,
              useHybridComposition: widget.forceHybridComposition,
            ),
            onCreateWindow: (controller, createWindowReq) async {
              final url = createWindowReq.request.url?.toString() ?? '';
              if (url.isNotEmpty) {
                await _handleFALink(context, url);
              }
              return true;   // We handled it ourselves – don’t open a new WebView
            },

            onLoadStop: (controller, url) async {
              String heightString = await controller.evaluateJavascript(
                source: "document.body.scrollHeight.toString()",
              );
              double height = double.tryParse(heightString) ?? 300.0;
              setState(() {
                _webViewHeight = height;
              });
              // Notify the parent that the webview is loaded and send the height.
              if (widget.onHeightChanged != null) {
                widget.onHeightChanged!(height);
              }

            },
            //below android version
            /*shouldOverrideUrlLoading: (controller, navAction) async {
              // Only care about the top frame.
              if (navAction.isForMainFrame) {
                final url = navAction.request.url.toString();
                await _handleFALink(context, url);
                return NavigationActionPolicy.CANCEL;   // stop webView
              }
              return NavigationActionPolicy.ALLOW;
            },
             */

            //below ios version
            /*shouldOverrideUrlLoading: (controller, navAction) async {
              // Only if this was a link tap (user-initiated)
              if (navAction.navigationType == NavigationType.LINK_ACTIVATED) {
                final tappedUrl = navAction.request.url.toString();

                if (tappedUrl == "https://www.furaffinity.net/") {
                  return NavigationActionPolicy.ALLOW;
                }
                await _handleFALink(context, tappedUrl);
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
              print('WebView Console: ${consoleMessage.message}');
            },
          ),
        );
      },
    );
  }
}


class SubmissionDescriptionWebViewScreen extends StatelessWidget {
  final String submissionId;
  const SubmissionDescriptionWebViewScreen({Key? key, required this.submissionId})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Text'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SubmissionDescriptionWebView(
        submissionId: submissionId,

        forceHybridComposition: true,
      ),
    );
  }
}
