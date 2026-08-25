//edit_submission_screen.dart

import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';
import 'package:fanotifier/features/image_tools/presentation/image_optimizer_launcher.dart';
import 'package:fanotifier/features/submissions/domain/edit_submission_page_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_file_picker_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_script_repository.dart';

class EditSubmissionScreen extends StatefulWidget {
  final String initialUrl;
  final String title;
  final EditSubmissionPageRepository? repository;

  const EditSubmissionScreen({
    super.key,
    required this.initialUrl,
    this.title = 'Edit Submission',
    this.repository,
  });

  @override
  State<EditSubmissionScreen> createState() => _EditSubmissionScreenState();
}

class _EditSubmissionScreenState extends State<EditSubmissionScreen> {
  static const _accent = Color(0xFFE09321);
  static const _thumbnailConstraints = ImageOptimizationConstraints(
    title: 'Optimize Submission Thumbnail',
    allowedFormats: {
      ImageOutputFormat.jpeg,
      ImageOutputFormat.png,
      ImageOutputFormat.gif,
    },
    maxBytes: 10 * 1024 * 1024,
    maxMegapixels: 3.7,
    maxMegapixelEquivalentWidth: 2560,
    maxMegapixelEquivalentHeight: 1440,
  );
  static const _sourceFileConstraints = ImageOptimizationConstraints(
    title: 'Optimize Source File',
    allowedFormats: {
      ImageOutputFormat.jpeg,
      ImageOutputFormat.png,
      ImageOutputFormat.gif,
    },
    maxBytes: 10 * 1024 * 1024,
    maxMegapixels: 3.7,
    maxMegapixelEquivalentWidth: 2560,
    maxMegapixelEquivalentHeight: 1440,
  );

  late final EditSubmissionPageRepository _repository;
  late final UploadFilePickerGateway _filePickerGateway;
  late final UploadWebViewScriptRepository _uploadScriptRepository;
  late final Future<void> _sessionPreparation;

  InAppWebViewController? _webViewController;
  final GlobalKey webViewKey = GlobalKey();

  bool get _isUpdateSubmissionScreen =>
      _repository.isUpdateSubmissionUrl(widget.initialUrl);

  String? get _updateFileInputName =>
      _repository.updateFileInputName(widget.initialUrl);

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? context.read<EditSubmissionPageRepository>();
    _filePickerGateway = context.read<UploadFilePickerGateway>();
    _uploadScriptRepository = context.read<UploadWebViewScriptRepository>();
    _sessionPreparation = _repository.prepareWebViewSession();
  }

  Future<void> _optimizeAndInjectImage() async {
    final inputName = _updateFileInputName;
    if (inputName == null) return;
    final constraints = inputName == 'newthumbnail'
        ? _thumbnailConstraints
        : _sourceFileConstraints;
    final selected = await pickAndOptimizeImage(
      context,
      _filePickerGateway,
      constraints,
    );
    if (selected == null || !mounted) return;

    var injected = false;
    final controller = _webViewController;
    if (controller != null) {
      try {
        final result = await controller.evaluateJavascript(
          source: _uploadScriptRepository.buildFileInputScript(
            selected,
            inputName: inputName,
          ),
        );
        injected = result == true || result?.toString() == 'true';
      } catch (_) {
        injected = false;
      }
    }
    if (!mounted) return;

    final actionLabel = inputName == 'newthumbnail'
        ? 'Update Thumbnail'
        : 'Update Submission';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          injected
              ? '${selected.fileName} is ready. Tap $actionLabel below to upload it.'
              : 'The upload field is not available on this page.',
        ),
      ),
    );
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
      allowFileAccess: true,
      allowContentAccess: true,
      allowFileAccessFromFileURLs: true,
      allowUniversalAccessFromFileURLs: true,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_updateFileInputName != null)
            IconButton(
              tooltip: 'Resize or compress an image',
              onPressed: _optimizeAndInjectImage,
              icon: const Icon(
                Icons.photo_size_select_small,
                color: _accent,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _sessionPreparation,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFE09321),
                ),
              );
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text('Unable to prepare the Fur Affinity session.'),
              );
            }

            return InAppWebView(
              key: webViewKey,
              initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
              initialSettings: settings,
              contextMenu: _buildContextMenu(),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStop: (controller, uri) async {
                if (uri != null &&
                    _repository.isSubmissionViewUrl(uri.toString())) {
                  await Future.delayed(const Duration(milliseconds: 50));
                  if (context.mounted) Navigator.pop(context, true);
                  return;
                }
                await _injectCustomCssAndJs();
              },
            );
          },
        ),
      ),
    );
  }
}
