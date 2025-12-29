import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'openjournal.dart';
import 'openpost.dart';

class CreateJournalScreen extends StatefulWidget {
  final String? uniqueNumber;
  const CreateJournalScreen({Key? key, this.uniqueNumber}) : super(key: key);

  @override
  _CreateJournalScreenState createState() => _CreateJournalScreenState();
}

class _CreateJournalScreenState extends State<CreateJournalScreen>
    with AutomaticKeepAliveClientMixin {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
      iOptions: IOSOptions(
          accountName: 'flutter_secure_storage_service',
          accessibility: KeychainAccessibility.first_unlock));
  late final String initialUrl;
  final String finalizeUrlPrefix = 'https://www.furaffinity.net/journal/';
  late final WebViewController _webViewController;

  bool _sfwEnabled = true;

  bool _isWaitingToOpenJournal = false;
  String? _journalId;
  int _countdown = 6;
  Timer? _timer;

  bool _handledCurrentJournal = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    if (widget.uniqueNumber != null) {
      initialUrl =
      'https://www.furaffinity.net/controls/journal/1/${widget.uniqueNumber}/';
    } else {
      initialUrl = 'https://www.furaffinity.net/controls/journal/';
    }
    _handledCurrentJournal = false;
    _loadSfwEnabled();
    _initializeWebViewController();
  }

  void _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
  }

  Future<void> _handlePossibleJournalSuccess(String url) async {
    if (_handledCurrentJournal) return;
    if (!url.startsWith(finalizeUrlPrefix)) return;

    final journalId = _extractJournalId(url);
    if (journalId == null) return;

    _handledCurrentJournal = true;
    debugPrint("Journal created with ID: $journalId");

    await _webViewController.loadRequest(Uri.parse(initialUrl));

    setState(() {
      _isWaitingToOpenJournal = true;
      _journalId = journalId;
      _countdown = 6;
    });

    _startCountdown();
  }

  void _initializeWebViewController() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) async {
            debugPrint("Page started loading: $url");

            if (url.startsWith(initialUrl)) {
              _handledCurrentJournal = false;
              debugPrint("Injecting journal form CSS and JavaScript");
              await _injectJournalFormCss();
            }

            await _handlePossibleJournalSuccess(url);
          },
          onPageFinished: (url) async {
            debugPrint("Page finished loading: $url");
            if (url.startsWith(initialUrl)) {
              await _injectJournalFormCss();
            }
          },
          onUrlChange: (change) async {
            final url = change.url;
            if (url == null) return;
            if (Platform.isIOS) {
              debugPrint("URL changed: $url");
              await _handlePossibleJournalSuccess(url);
            }
          },
          onWebResourceError: (error) {
            debugPrint("Web resource error: $error");
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));

    addFileSelectionListener();
    _setCookies();
  }

  String? _extractJournalId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'journal') {
        return uri.pathSegments[1];
      }
    } catch (e) {
      debugPrint('Error parsing journal ID: $e');
    }
    return null;
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_countdown == 1) {
        timer.cancel();
        if (_journalId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OpenJournal(uniqueNumber: _journalId!),
            ),
          ).then((_) {
            setState(() {
              _isWaitingToOpenJournal = false;
              _countdown = 6;
            });
          });
        }
      } else {
        setState(() {
          _countdown--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _injectJournalFormCss() async {
    await _webViewController.runJavaScript('''
      (function() {
        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = \`
          .sidebar {
            display: none !important;
          }
          #journal-form {
            margin: 0 auto !important;
            padding: 0 !important;
            width: 100% !important;
            max-width: 600px !important;
            background-color: #ffffff !important;
            box-shadow: 0 0 10px rgba(0,0,0,0.1) !important;
            border-radius: 8px !important;
          }
          #journal-form .section-body {
            padding: 10px !important;
          }
          .mobile-navigation,
          #header,
          #footer,
          .leaderboardAd,
          .news-block,
          .mobile-notification-bar,
          nav#ddmenu,
          .online-stats,
          .footnote,
          .footerAds,
          .floatleft,
          .submenu-trigger,
          .banner-svg,
          .leaderboardAd,
          .newsBlock,
          .footerAds__column,
          .message-bar-desktop,
          .notification-container,
          .dropdown,
          .dropzone { 
            display: none !important; 
          }
        \`;
        document.head.appendChild(style);

        var headers = document.querySelectorAll('.section-header h2');
        headers.forEach(function(header) {
          if (header.textContent.trim() === 'Previous Journals') {
            var section = header.closest('section');
            if (section) {
              section.style.display = 'none';
            }
          }
        });
      })();
    ''');
    debugPrint("CSS and JavaScript injection completed.");
  }

  void addFileSelectionListener() async {
    if (Platform.isAndroid) {
      final androidController =
      _webViewController.platform as AndroidWebViewController;
      await androidController.setOnShowFileSelector(_androidFilePicker);
    }
  }

  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'pdf'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        return [file.uri.toString()];
      }
    } catch (e) {
      debugPrint("Error selecting file: $e");
    }
    return [];
  }

  Future<void> _setCookies() async {
    List<String> secureCookieKeys = ['a', 'b', 'cc', 'folder', 'nodesc', 'sz'];
    for (var key in secureCookieKeys) {
      String storageKey = 'fa_cookie_$key';
      String? cookieValue = await _secureStorage.read(key: storageKey);
      if (cookieValue != null && cookieValue.isNotEmpty) {
        await _webViewController.runJavaScript(
          '''
          document.cookie = "$key=$cookieValue; path=/; domain=.furaffinity.net; secure; httponly";
          ''',
        );
      }
    }

    if (_sfwEnabled) {
      await _webViewController.runJavaScript(
        '''
        document.cookie = "sfw=1; path=/; domain=.furaffinity.net; secure; httponly";
        ''',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Journal'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _webViewController),
            if (_isWaitingToOpenJournal)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.7),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Waiting to open your journal',
                          style:
                          TextStyle(color: Colors.white, fontSize: 24),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '$_countdown',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 48),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
