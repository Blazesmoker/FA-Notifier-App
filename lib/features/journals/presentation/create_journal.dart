import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:FANotifier/shared/widgets/tags_and_codes_webview_widget.dart';
import 'package:FANotifier/features/journals/presentation/openjournal.dart';

class CreateJournalScreen extends StatefulWidget {
  final String? uniqueNumber;
  final VoidCallback? onJournalSubmitted;

  const CreateJournalScreen({
    Key? key,
    this.uniqueNumber,
    this.onJournalSubmitted,
  }) : super(key: key);

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

  InAppWebViewController? _webViewController;
  final GlobalKey webViewKey = GlobalKey();

  bool _sfwEnabled = true;

  bool _isWaitingToOpenJournal = false;
  String? _journalId;
  int _countdown = 6;
  Timer? _timer;

  bool _handledCurrentJournal = false;
  bool _didNotifyJournalSubmitted = false;

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
  }

  void _loadSfwEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwEnabled = prefs.getBool('sfwEnabled') ?? true;
    });
  }

  Future<void> _handlePossibleJournalSuccess(String? url) async {
    if (_handledCurrentJournal) return;
    if (url == null || !url.startsWith(finalizeUrlPrefix)) return;

    final journalId = _extractJournalId(url);
    if (journalId == null) return;

    _handledCurrentJournal = true;
    _notifyJournalSubmitted();
    debugPrint("Journal created with ID: $journalId");

    await _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(initialUrl)));

    setState(() {
      _isWaitingToOpenJournal = true;
      _journalId = journalId;
      _countdown = 6;
    });

    _startCountdown();
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
              builder: (context) => OpenJournal(
                uniqueNumber: _journalId!,
                onJournalMutated: widget.onJournalSubmitted,
              ),
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

  bool _isOnEditorPage(String? url) {
    if (url == null) return false;
    return url.contains('/controls/journal');
  }

  Future<void> _detectJournalViaDom(String? currentUrl) async {
    if (_handledCurrentJournal) return;
    if (_webViewController == null) return;
    if (_isOnEditorPage(currentUrl)) return;

    final result = await _webViewController!.evaluateJavascript(source: '''
(function() {
  const links = document.querySelectorAll('a[href^="/journal/"]');
  for (const link of links) {
    const href = link.getAttribute('href');
    if (href && href.endsWith('/')) return href;
  }
  return null;
})();
''');

    if (result == null) return;

    final fullUrl = 'https://www.furaffinity.net' + result;
    final journalId = _extractJournalId(fullUrl);
    if (journalId == null) return;

    _handledCurrentJournal = true;
    _notifyJournalSubmitted();

    setState(() {
      _isWaitingToOpenJournal = true;
      _journalId = journalId;
      _countdown = 6;
    });

    _startCountdown();
  }

  void _notifyJournalSubmitted() {
    if (_didNotifyJournalSubmitted) return;
    _didNotifyJournalSubmitted = true;
    widget.onJournalSubmitted?.call();
  }

  Future<void> _setCookies() async {
    final cookieManager = CookieManager.instance();
    final prefs = await SharedPreferences.getInstance();
    final sfwValue = (prefs.getBool('sfwEnabled') ?? true) ? '1' : '0';
    final cookieKeys = ['a', 'b', 'cc', 'cf_clearance', 'folder', 'nodesc', 'sz', 'sfw'];

    for (final key in cookieKeys) {
      final value = key == 'sfw'
          ? sfwValue
          : (await _secureStorage.read(key: 'fa_cookie_$key') ?? '');

      if (value.isNotEmpty) {
        await cookieManager.setCookie(
          url: WebUri('https://www.furaffinity.net'),
          name: key,
          value: value,
          domain: '.furaffinity.net',
          path: '/',
          isSecure: true,
          isHttpOnly: true,
        );
      }
    }
  }

  Future<void> _injectJournalFormCss() async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(source: '''
      (function() {
        if (window.__journalCssInjected) return;
        window.__journalCssInjected = true;

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

  Future<void> _wrapSelection(String tag) async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(source: '''
(function(){
  var open='[$tag]';
  var close='[/$tag]';
  var active=document.activeElement;

  if (active && (active.tagName==='TEXTAREA' || (active.tagName==='INPUT' && active.type==='text'))) {
    var s=active.selectionStart, e=active.selectionEnd;
    if (s!=null && e!=null && e>s) {
      var before=active.value.substring(0,s);
      var sel=active.value.substring(s,e);
      var after=active.value.substring(e);
      active.value=before+open+sel+close+after;
      active.selectionStart=before.length+open.length;
      active.selectionEnd=active.selectionStart+sel.length;
      active.dispatchEvent(new Event('input',{bubbles:true}));
    }
    return;
  }

  var sel=window.getSelection();
  if (!sel || sel.rangeCount===0) return;
  var r=sel.getRangeAt(0);
  var t=sel.toString();
  var node=document.createTextNode(open+t+close);
  r.deleteContents();
  r.insertNode(node);

  var nr=document.createRange();
  nr.setStartAfter(node);
  nr.collapse(true);
  sel.removeAllRanges();
  sel.addRange(nr);
})();
''');
  }

  ContextMenu _buildContextMenu() {
    return ContextMenu(
      menuItems: [
        ContextMenuItem(id: 1, title: 'Bold', action: () => _wrapSelection('b')),
        ContextMenuItem(id: 2, title: 'Italic', action: () => _wrapSelection('i')),
        ContextMenuItem(id: 3, title: 'Underline', action: () => _wrapSelection('u')),
        ContextMenuItem(id: 4, title: 'Align Left', action: () => _wrapSelection('left')),
        ContextMenuItem(id: 5, title: 'Align Center', action: () => _wrapSelection('center')),
        ContextMenuItem(id: 6, title: 'Align Right', action: () => _wrapSelection('right')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      useShouldOverrideUrlLoading: false,
      verticalScrollBarEnabled: true,
      horizontalScrollBarEnabled: false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Journal'),
        centerTitle: true,
        actions: [
          InfoIconButton(
            url: 'https://www.furaffinity.net/help/#tags-and-codes',
            title: 'Tags & Codes',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              key: webViewKey,
              initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
              initialSettings: settings,
              contextMenu: _buildContextMenu(),
              onWebViewCreated: (controller) async {
                _webViewController = controller;
                await _setCookies();
              },
              onLoadStart: (controller, uri) async {
                _webViewController = controller;
                debugPrint("Page started loading: $uri");
                if (uri != null && uri.toString().startsWith(initialUrl)) {
                  debugPrint("Injecting journal form CSS and JavaScript");
                  await _injectJournalFormCss();
                }
              },
              onLoadStop: (controller, uri) async {
                debugPrint("Page finished loading: $uri");

                if (uri != null && uri.toString().startsWith(initialUrl)) {
                  await _injectJournalFormCss();
                }

                await _handlePossibleJournalSuccess(uri?.toString());
                await _detectJournalViaDom(uri?.toString());
              },
              onUpdateVisitedHistory: (controller, uri, androidIsReload) async {
                if (uri != null) {
                  await _handlePossibleJournalSuccess(uri.toString());
                }
              },

            ),
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
                          style: TextStyle(color: Colors.white, fontSize: 24),
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
