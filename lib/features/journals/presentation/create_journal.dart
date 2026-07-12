import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'package:FANotifier/features/journals/domain/create_journal_repository.dart';
import 'package:FANotifier/shared/widgets/tags_and_codes_webview_widget.dart';
import 'package:FANotifier/features/journals/presentation/openjournal.dart';

class CreateJournalScreen extends StatefulWidget {
  final String? uniqueNumber;
  final VoidCallback? onJournalSubmitted;
  final CreateJournalRepository? repository;

  const CreateJournalScreen({
    Key? key,
    this.uniqueNumber,
    this.onJournalSubmitted,
    this.repository,
  }) : super(key: key);

  @override
  _CreateJournalScreenState createState() => _CreateJournalScreenState();
}

class _CreateJournalScreenState extends State<CreateJournalScreen>
    with AutomaticKeepAliveClientMixin {
  late final CreateJournalRepository _createJournalRepository;
  late final String initialUrl;

  InAppWebViewController? _webViewController;
  final GlobalKey webViewKey = GlobalKey();

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
    _createJournalRepository =
        widget.repository ?? context.read<CreateJournalRepository>();
    initialUrl = _createJournalRepository.buildInitialUrl(widget.uniqueNumber);
    _handledCurrentJournal = false;
  }

  Future<void> _handlePossibleJournalSuccess(String? url) async {
    if (_handledCurrentJournal) return;
    if (!_createJournalRepository.isJournalFinalizeUrl(url)) return;

    final journalId = _createJournalRepository.extractJournalId(url!);
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

  Future<void> _detectJournalViaDom(String? currentUrl) async {
    if (_handledCurrentJournal) return;
    if (_webViewController == null) return;
    if (_createJournalRepository.isEditorPage(currentUrl)) return;

    final result = await _webViewController!.evaluateJavascript(
      source: _createJournalRepository.buildFindCreatedJournalPathScript(),
    );

    if (result == null) return;

    final fullUrl = _createJournalRepository.buildFullJournalUrl(result);
    final journalId = _createJournalRepository.extractJournalId(fullUrl);
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

  Future<void> _injectJournalFormCss() async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(
      source: _createJournalRepository.buildJournalFormInjectionScript(),
    );
    debugPrint("CSS and JavaScript injection completed.");
  }

  Future<void> _wrapSelection(String tag) async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(
      source: _createJournalRepository.buildJournalWrapSelectionScript(tag),
    );
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
                await _createJournalRepository.prepareWebViewSession();
              },
              onLoadStart: (controller, uri) async {
                _webViewController = controller;
                debugPrint("Page started loading: $uri");
                if (uri != null &&
                    _createJournalRepository.shouldInjectEditorAssets(
                      currentUrl: uri.toString(),
                      initialUrl: initialUrl,
                    )) {
                  debugPrint("Injecting journal form CSS and JavaScript");
                  await _injectJournalFormCss();
                }
              },
              onLoadStop: (controller, uri) async {
                debugPrint("Page finished loading: $uri");

                if (uri != null &&
                    _createJournalRepository.shouldInjectEditorAssets(
                      currentUrl: uri.toString(),
                      initialUrl: initialUrl,
                    )) {
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
                  color: Colors.black.withValues(alpha: 0.7),
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
