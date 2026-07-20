import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:fanotifier/features/upload/domain/submission_template.dart';
import 'package:fanotifier/features/upload/domain/upload_selected_file.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_results.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_script_repository.dart';

class UploadWebViewBridge {
  UploadWebViewBridge({
    required UploadWebViewScriptRepository scriptRepository,
  }) : _scriptRepository = scriptRepository;

  final UploadWebViewScriptRepository _scriptRepository;
  InAppWebViewController? _controller;

  void attach(InAppWebViewController controller) {
    _controller = controller;
  }

  Future<void> wrapSelection(String tag) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source: _scriptRepository.buildWrapSelectionScript(tag),
    );
  }

  Future<void> injectInitialPage({required bool isIOS}) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source: _scriptRepository.buildInitialPageScript(isIOS: isIOS),
    );
  }

  Future<void> injectFinalizePage({required bool isIOS}) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source: _scriptRepository.buildFinalizePageScript(isIOS: isIOS),
    );
  }

  Future<UploadClearFormResult> clearFinalizeForm() async {
    final controller = _controller;
    if (controller == null) {
      return const UploadClearFormResult(UploadClearFormStatus.unavailable);
    }

    try {
      final raw = await controller.evaluateJavascript(
        source: _scriptRepository.buildClearFinalizeFormScript(),
      );
      return _scriptRepository.decodeClearFormResult(raw);
    } catch (_) {
      return const UploadClearFormResult(UploadClearFormStatus.failed);
    }
  }

  Future<UploadFinalizeFieldsReadResult> readFinalizeFields() async {
    final controller = _controller;
    if (controller == null) {
      return const UploadFinalizeFieldsReadResult(
        status: UploadFinalizeFieldsReadStatus.unavailable,
      );
    }

    try {
      final raw = await controller.evaluateJavascript(
        source: _scriptRepository.buildReadTemplateFieldsScript(),
      );
      return _scriptRepository.decodeFinalizeFieldsReadResult(raw);
    } catch (e) {
      debugPrint('Exception in _readFinalizeFields: $e');
      return const UploadFinalizeFieldsReadResult(
        status: UploadFinalizeFieldsReadStatus.failed,
      );
    }
  }

  Future<UploadTemplateApplyResult> applyTemplate(
    SubmissionTemplateFields fields,
  ) async {
    final controller = _controller;
    if (controller == null) {
      return const UploadTemplateApplyResult(
        status: UploadTemplateApplyStatus.failed,
      );
    }

    try {
      final raw = await controller.evaluateJavascript(
        source: _scriptRepository.buildApplyTemplateScript(fields),
      );
      return _scriptRepository.decodeTemplateApplyResult(raw);
    } catch (_) {
      return const UploadTemplateApplyResult(
        status: UploadTemplateApplyStatus.failed,
      );
    }
  }

  Future<void> injectFilePickerHandler() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source: _scriptRepository.buildFilePickerHandlerScript(),
    );
  }

  Future<void> injectFile(UploadSelectedFile selectedFile) async {
    await _controller!.evaluateJavascript(
      source: _scriptRepository.buildFileInputScript(selectedFile),
    );
  }
}
