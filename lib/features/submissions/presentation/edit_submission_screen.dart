//edit_submission_screen.dart

import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/submissions/domain/edit_submission_page_repository.dart';

class EditSubmissionScreen extends StatefulWidget {
  final String initialUrl;
  final EditSubmissionPageRepository? repository;

  const EditSubmissionScreen({
    super.key,
    required this.initialUrl,
    this.repository,
  });

  @override
  State<EditSubmissionScreen> createState() => _EditSubmissionScreenState();
}

class _EditSubmissionScreenState extends State<EditSubmissionScreen> {
  late final EditSubmissionPageRepository _repository;

  InAppWebViewController? _webViewController;
  final GlobalKey webViewKey = GlobalKey();

  bool get _isUpdateSubmissionScreen =>
      _repository.isUpdateSubmissionUrl(widget.initialUrl);

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? context.read<EditSubmissionPageRepository>();
  }

  Future<void> _injectCustomCssAndJs() async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(
      source: _repository.buildBaseScript(),
    );

    if (_isUpdateSubmissionScreen) {
      await _webViewController!.evaluateJavascript(
        source: _repository.buildMoveSubmissionFileCellScript(),
      );
    }
  }

  Future<void> _wrapSelection(String tag) async {
    if (_webViewController == null) return;

    await _webViewController!.evaluateJavascript(
      source: _repository.buildWrapSelectionScript(tag),
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
            await _repository.prepareWebViewSession();
          },
          onLoadStart: (controller, uri) async {
            await _injectCustomCssAndJs();
          },
          onLoadStop: (controller, uri) async {
            await _injectCustomCssAndJs();
            if (uri != null &&
                _repository.isSubmissionViewUrl(uri.toString())) {
              await Future.delayed(const Duration(milliseconds: 50));
              if (context.mounted) Navigator.pop(context, true);
            }
          },
        ),
      ),
    );
  }
}
