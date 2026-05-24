//edit_submission_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:FANotifier/features/submissions/data/edit_submission_navigation_service.dart';
import 'package:FANotifier/features/submissions/data/edit_submission_webview_scripts.dart';
import 'package:FANotifier/shared/fa/fa_webview_cookie_service.dart';

class EditSubmissionScreen extends StatefulWidget {
  final String initialUrl;

  const EditSubmissionScreen({
    Key? key,
    required this.initialUrl,
  }) : super(key: key);

  @override
  State<EditSubmissionScreen> createState() => _EditSubmissionScreenState();
}

class _EditSubmissionScreenState extends State<EditSubmissionScreen> {
  final EditSubmissionNavigationService _navigationService =
      const EditSubmissionNavigationService();
  late final FAWebViewCookieService _webViewCookieService;

  InAppWebViewController? _webViewController;
  final GlobalKey webViewKey = GlobalKey();

  bool get _isUpdateSubmissionScreen =>
      _navigationService.isUpdateSubmissionUrl(widget.initialUrl);

  @override
  void initState() {
    super.initState();
    _webViewCookieService = FAWebViewCookieService();
  }

  Future<void> _injectCustomCssAndJs() async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(
      source: buildEditSubmissionBaseScript(),
    );

    if (_isUpdateSubmissionScreen) {
      await _webViewController!.evaluateJavascript(
        source: buildMoveSubmissionFileCellScript(),
      );
    }
  }

  Future<void> _wrapSelection(String tag) async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(
      source: buildWrapSelectionScript(tag),
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
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      useShouldOverrideUrlLoading: true,
      verticalScrollBarEnabled: true,
      horizontalScrollBarEnabled: false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Submission'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: InAppWebView(
          key: webViewKey,
          initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
          initialSettings: settings,
          contextMenu: _buildContextMenu(),
          onWebViewCreated: (controller) async {
            _webViewController = controller;
            await _webViewCookieService.setCookies();
          },
          onLoadStart: (controller, uri) async {
            await _injectCustomCssAndJs();
          },
          onLoadStop: (controller, uri) async {
            await _injectCustomCssAndJs();
            if (uri != null &&
                _navigationService.isSubmissionViewUrl(uri.toString())) {
              await Future.delayed(const Duration(milliseconds: 50));
              if (mounted) Navigator.pop(context, true);
            }
          },
        ),
      ),
    );
  }
}
