// lib/screens/upload_submission_screen.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:fanotifier/shared/widgets/tags_and_codes_webview_widget.dart';
import 'package:fanotifier/features/submissions/presentation/openpost.dart';
import 'package:fanotifier/features/upload/domain/submission_template.dart';
import 'package:fanotifier/features/upload/domain/submission_template_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_file_picker_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_navigation_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_permission_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_results.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_script_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_session_gateway.dart';
import 'package:fanotifier/features/upload/presentation/submission_templates_screen.dart';
import 'package:fanotifier/features/upload/presentation/upload_webview_bridge.dart';
import 'package:provider/provider.dart';

class UploadSubmissionScreen extends StatefulWidget {
  const UploadSubmissionScreen({super.key});

  @override
  State<UploadSubmissionScreen> createState() =>
      _UploadSubmissionScreenState();
}

class _UploadSubmissionScreenState extends State<UploadSubmissionScreen> with TickerProviderStateMixin {
  static const Color _accent = Color(0xFFE09321);

  late final UploadWebViewBridge _webViewBridge;
  late final UploadPermissionGateway _permissionGateway;
  late final UploadFilePickerGateway _filePickerGateway;
  late final UploadNavigationRepository _navigationRepository;
  late final SubmissionTemplateRepository _templateRepository;
  late final UploadWebViewSessionGateway _webViewSessionGateway;

  String get initialUrl => _navigationRepository.initialUrl;
  String get finalizeUrl => _navigationRepository.finalizeUrl;
  final GlobalKey webViewKey = GlobalKey();

  bool _isWaitingToOpenSubmission = false;
  int? _submissionId;
  int _countdown = 6;
  Timer? _timer;
  bool _isProcessingUploadSuccess = false;
  bool _isFinalizeReady = false;

  bool _toolsMenuOpen = false;
  late final AnimationController _toolsMenuController;
  late final Animation<double> _toolsMenuSize;
  late final Animation<double> _toolsMenuFade;
  late final Animation<Offset> _toolsMenuSlide;

  @override
  void initState() {
    super.initState();
    _webViewBridge = UploadWebViewBridge(
      scriptRepository: context.read<UploadWebViewScriptRepository>(),
    );
    _permissionGateway = context.read<UploadPermissionGateway>();
    _filePickerGateway = context.read<UploadFilePickerGateway>();
    _navigationRepository = context.read<UploadNavigationRepository>();
    _templateRepository = context.read<SubmissionTemplateRepository>();
    _webViewSessionGateway = context.read<UploadWebViewSessionGateway>();
    _permissionGateway.requestInitialPermissions();

    _toolsMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
    );

    final curveIn = CurvedAnimation(parent: _toolsMenuController, curve: Curves.easeInOut);
    _toolsMenuSize = curveIn;
    _toolsMenuFade = curveIn;
    _toolsMenuSlide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _toolsMenuController, curve: Curves.easeOutCubic));

  }

  void _setFinalizeReady(bool value) {
    if (!mounted) return;
    if (_isFinalizeReady == value) return;
    setState(() => _isFinalizeReady = value);
    if (!value) {
      _closeToolsMenu();
    }
  }

  Future<void> _openToolsMenu() async {
    if (!mounted) return;
    if (_toolsMenuOpen && _toolsMenuController.status == AnimationStatus.forward) return;
    if (_toolsMenuController.isAnimating) return;

    setState(() => _toolsMenuOpen = true);
    await _toolsMenuController.forward(from: _toolsMenuController.value.clamp(0.0, 1.0));
  }

  Future<void> _closeToolsMenu() async {
    if (!mounted) return;
    if (!_toolsMenuOpen && _toolsMenuController.value == 0) return;
    if (_toolsMenuController.isAnimating) return;

    await _toolsMenuController.reverse(from: _toolsMenuController.value.clamp(0.0, 1.0));
    if (!mounted) return;
    setState(() => _toolsMenuOpen = false);
  }

  void _toggleToolsMenu() {
    if (!mounted) return;
    if (_toolsMenuOpen || _toolsMenuController.value > 0) {
      _closeToolsMenu();
    } else {
      _openToolsMenu();
    }
  }

  Future<void> _handleLoadUrl(String? url) async {
    if (url == null) return;

    debugPrint("Page loading: $url");
    _setFinalizeReady(_navigationRepository.isFinalizeUrl(url));

    // Prevent double-triggering
    if (_navigationRepository.isUploadSuccessfulUrl(url) &&
        !_isProcessingUploadSuccess) {
      _isProcessingUploadSuccess = true;

      final submissionId = _navigationRepository.extractSubmissionId(url);

      if (submissionId != null) {


        if (!mounted) {
          _isProcessingUploadSuccess = false;
          return;
        }

        setState(() {
          _isWaitingToOpenSubmission = true;
          _submissionId = submissionId;
          _countdown = 6;
        });

        _startCountdown();


        await Future.delayed(const Duration(seconds: 2));
        _isProcessingUploadSuccess = false;
      } else {
        _isProcessingUploadSuccess = false;
      }
    } else if (_navigationRepository.isInitialSubmitUrl(url)) {
      await _injectInitialCss();
    } else if (_navigationRepository.isFinalizeUrl(url)) {
      await _injectFinalizeCss();
    }
  }

  Future<void> _wrapSelection(String tag) async {
    await _webViewBridge.wrapSelection(tag);
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

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_countdown == 1) {
        timer.cancel();

        Navigator.push(
          context,
          OpenPost.route(
            imageUrl: '',
            uniqueNumber: _submissionId.toString(),
          ),
        ).then((_) {
          if (!mounted) return;
          Navigator.pop(context);
        });
      } else {
        if (!mounted) return;
        setState(() {
          _countdown--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _toolsMenuController.dispose();
    super.dispose();
  }

  Future<void> _injectInitialCss() async {
    await _webViewBridge.injectInitialPage(isIOS: Platform.isIOS);
  }

  Future<void> _injectFinalizeCss() async {
    await _webViewBridge.injectFinalizePage(isIOS: Platform.isIOS);
  }

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clearFinalizeFormToDefaults() async {
    try {
      final result = await _webViewBridge.clearFinalizeForm();
      if (result.status == UploadClearFormStatus.unavailable) return;
      if (result.status == UploadClearFormStatus.cleared) {
        _showSnack('Form cleared.', isError: false);
      } else {
        _showSnack('Failed to clear form.', isError: true);
      }
    } catch (_) {
      _showSnack('Failed to clear form.', isError: true);
    }
  }

  Future<SubmissionTemplateFields?> _readFinalizeFields() async {
    final result = await _webViewBridge.readFinalizeFields();
    return result.fields;
  }

  Future<String?> _promptTemplateName() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _accent, width: 0.5),
          borderRadius: BorderRadius.circular(22),
        ),
        title: const Text('Save Template', style: TextStyle(color: _accent)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Template name',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _accent, width: 0.8),
              borderRadius: BorderRadius.circular(14),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _accent, width: 1.2),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );

    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> _saveTemplateFlow() async {
    debugPrint('_saveTemplateFlow called');

    if (!_isFinalizeReady) {
      _showSnack('Please navigate to the finalize page first.', isError: true);
      return;
    }

    try {
      // Wait a bit to ensure the page is fully loaded
      await Future.delayed(const Duration(milliseconds: 300));

      final fields = await _readFinalizeFields();
      if (fields == null) {
        _showSnack('Failed to read finalize form. Make sure you are on the finalize page.', isError: true);
        return;
      }

      debugPrint('Successfully read fields: ${fields.toJson()}');

      final name = await _promptTemplateName();

      if (name == null) {
        return;
      }

      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        _showSnack('Template name cannot be empty.', isError: true);
        return;
      }

      await _templateRepository.saveTemplate(
        name: trimmed,
        fields: fields,
      );

      if (!mounted) return;
      _showSnack('Template saved.', isError: false);
    } catch (e) {
      debugPrint('Error saving template: $e');
      if (!mounted) return;
      _showSnack('Failed to save template: ${e.toString()}', isError: true);
    }
  }


  Future<void> _openTemplatesScreen() async {
    final selected = await Navigator.push<SubmissionTemplate?>(
      context,
      MaterialPageRoute(
        builder: (context) => SubmissionTemplatesScreen(
          repository: _templateRepository,
        ),
      ),
    );

    if (selected == null) return;
    await _applyTemplate(selected);
  }

  Future<void> _applyTemplate(SubmissionTemplate template) async {
    try {
      final result = await _webViewBridge.applyTemplate(template.fields);
      if (result.status == UploadTemplateApplyStatus.failed) {
        _showSnack('Failed to apply template.', isError: true);
        return;
      }

      if (result.status == UploadTemplateApplyStatus.partiallyApplied) {
        _showSnack(
          'Could not apply: ${result.failedFields.join(', ')}',
          isError: true,
        );
      } else {
        _showSnack('Template applied.', isError: false);
      }
    } catch (_) {
      _showSnack('Failed to apply template.', isError: true);
    }
  }

  double _measureTextWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  Widget _toolsMenu(BuildContext context) {
    const labels = <String>['Templates', 'Save template', 'Clear'];
    const textStyle = TextStyle(color: Colors.white, fontSize: 14);
    const rowHPad = 12.0;
    const gap = 12.0;
    const iconSize = 24.0;
    const extraTextPad = 16.0;

    double maxTextWidth = 0;
    for (final t in labels) {
      final w = _measureTextWidth(context, t, textStyle);
      if (w > maxTextWidth) maxTextWidth = w;
    }

    final desiredMenuWidth = maxTextWidth + extraTextPad + (rowHPad * 2) + gap + iconSize;

    final screenW = MediaQuery.of(context).size.width;
    final maxAvailable = max(0.0, screenW - 16);
    final menuWidth = min(desiredMenuWidth, maxAvailable);

    final menu = Material(
      color: Colors.transparent,
      child: Container(
        width: menuWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accent, width: 0.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _toolsItem(
              icon: Icons.list_alt_outlined,
              text: 'Templates',
              onTap: () {
                _closeToolsMenu();
                _openTemplatesScreen();
              },
            ),
            _divider(),
            _toolsItem(
              icon: Icons.save_outlined,
              text: 'Save template',
              onTap: () {
                _closeToolsMenu();
                _saveTemplateFlow();
              },
            ),
            _divider(),
            _toolsItem(
              icon: Icons.cleaning_services_outlined,
              text: 'Clear',
              onTap: () {
                _closeToolsMenu();
                _clearFinalizeFormToDefaults();
              },
            ),
          ],
        ),
      ),
    );

    return Align(
      alignment: Alignment.topRight,
      child: FadeTransition(
        opacity: _toolsMenuFade,
        child: SlideTransition(
          position: _toolsMenuSlide,
          child: SizeTransition(
            sizeFactor: _toolsMenuSize,
            axis: Axis.vertical,
            alignment: const AlignmentDirectional(-1.0, -1.0),
            child: menu,
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(height: 1, color: _accent.withValues(alpha: 0.18));

  Widget _toolsItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    text,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(icon, color: _accent, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebView() {
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

    return InAppWebView(
      key: webViewKey,
      initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
      initialSettings: settings,
      contextMenu: _buildContextMenu(),
      onWebViewCreated: (controller) async {
        _webViewBridge.attach(controller);
        await _webViewSessionGateway.setCookies();

        controller.addJavaScriptHandler(
          handlerName: 'selectFile',
          callback: (args) async {
            await _selectAndInjectFile();
          },
        );
      },

      onLoadStart: (controller, uri) async {
        _webViewBridge.attach(controller);
        await _handleLoadUrl(uri?.toString());
      },
      onLoadStop: (controller, uri) async {
        await _handleLoadUrl(uri?.toString());

        await _injectFilePickerHandler();
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;

        if (Platform.isIOS &&
            uri != null &&
            _navigationRepository.shouldBlockIosHost(uri.host)) {
          debugPrint('Blocking ad/tracker request on iOS: ${uri.host}');
          return NavigationActionPolicy.CANCEL;
        }


        return NavigationActionPolicy.ALLOW;
      },
    );
  }

  Future<void> _injectFilePickerHandler() async {
    await _webViewBridge.injectFilePickerHandler();
  }

  Future<void> _selectAndInjectFile() async {
    try {
      final source = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: _accent, width: 0.5),
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Select source',
            style: TextStyle(color: _accent),
          ),
          content: const Text(
            'Choose between Files or Gallery',
            style: TextStyle(color: Colors.white70),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('files'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Files',
                    style: TextStyle(color: _accent),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.insert_drive_file, color: _accent),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('gallery'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Gallery',
                    style: TextStyle(color: _accent),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.image, color: _accent),
                ],
              ),
            ),
          ],
        ),
      );

      if (source == null) return;

      if (source != 'files' && source != 'gallery') {
        debugPrint('Failed to read file bytes');
        return;
      }

      final selectedFile = source == 'files'
          ? await _filePickerGateway.pickFile()
          : await _filePickerGateway.pickGalleryImage();
      if (selectedFile == null) return;

      await _webViewBridge.injectFile(selectedFile);

      debugPrint('File loaded successfully: ${selectedFile.fileName}');
    } catch (e) {
      debugPrint('Error selecting file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuVisible = _isFinalizeReady && (_toolsMenuOpen || _toolsMenuController.value > 0);
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _timer?.cancel();
              setState(() {
                _isWaitingToOpenSubmission = false;
              });
              Navigator.pop(context);
            },
          ),
          centerTitle: false,
          titleSpacing: 0,
          title: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: const Text(
                'Upload Submission',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          actions: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: _isFinalizeReady
                      ? const Offset(14.0, 0)
                      : Offset.zero,
                  child: InfoIconButton(
                    url: 'https://www.furaffinity.net/help/#tags-and-codes',
                    title: 'Tags & Codes',
                  ),
                ),
                if (_isFinalizeReady)
                  IconButton(
                    tooltip: 'More',
                    icon: Icon(
                      (_toolsMenuOpen || _toolsMenuController.value > 0)
                          ? Icons.close
                          : Icons.more_vert,
                      color: _accent,
                    ),
                    onPressed: _toggleToolsMenu,
                  ),
              ],
            ),
          ],

        ),


        body: Stack(
          children: [
            _buildWebView(),
            if (menuVisible)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeToolsMenu,
                  child: const SizedBox.shrink(),
                ),
              ),
            if (_isFinalizeReady)
              Positioned(
                top: 8,
                right: 8,
                child: IgnorePointer(
                  ignoring: !_toolsMenuOpen && _toolsMenuController.value == 0,
                  child: _toolsMenu(context),
                ),
              ),
            if (_isWaitingToOpenSubmission)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Waiting to open your submission',
                          style: TextStyle(color: Colors.white, fontSize: 24),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '$_countdown',
                          style: const TextStyle(color: Colors.white, fontSize: 48),
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
