import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:FANotifier/features/upload/data/upload_file_webview_scripts.dart';
import 'package:FANotifier/features/upload/data/upload_js_result_decoder.dart';
import 'package:FANotifier/features/upload/data/upload_page_webview_scripts.dart';
import 'package:FANotifier/features/upload/data/upload_template_js_builder.dart';
import 'package:FANotifier/features/upload/domain/submission_template.dart';
import 'package:FANotifier/features/upload/domain/upload_selected_file.dart';
import 'package:FANotifier/features/upload/domain/upload_webview_results.dart';

class UploadWebViewBridge {
  UploadWebViewBridge({
    UploadJsResultDecoder decoder = const UploadJsResultDecoder(),
  }) : _decoder = decoder;

  final UploadJsResultDecoder _decoder;
  InAppWebViewController? _controller;

  void attach(InAppWebViewController controller) {
    _controller = controller;
  }

  Future<void> wrapSelection(String tag) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source: buildUploadWrapSelectionScript(tag),
    );
  }

  Future<void> injectInitialPage({required bool isIOS}) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source: buildUploadInitialPageScript(isIOS: isIOS),
    );
  }

  Future<void> injectFinalizePage({required bool isIOS}) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(
      source: buildUploadFinalizePageScript(isIOS: isIOS),
    );
  }

  Future<UploadClearFormResult> clearFinalizeForm() async {
    final controller = _controller;
    if (controller == null) {
      return const UploadClearFormResult(UploadClearFormStatus.unavailable);
    }

    try {
      final raw = await controller.evaluateJavascript(
        source: buildClearFinalizeFormScript(),
      );
      final map = _decoder.decodeMap(raw);
      if (map != null && map['ok'] == true) {
        return const UploadClearFormResult(UploadClearFormStatus.cleared);
      }
      return const UploadClearFormResult(UploadClearFormStatus.failed);
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
        source: buildReadSubmissionTemplateFieldsScript(),
      );
      final map = _decoder.decodeMap(raw);
      if (map == null) {
        debugPrint('Failed to decode JavaScript result');
        return const UploadFinalizeFieldsReadResult(
          status: UploadFinalizeFieldsReadStatus.failed,
        );
      }

      if (map['ok'] != true) {
        final error = map['error'] ?? 'Unknown error';
        debugPrint('JavaScript error reading form: $error');
        return const UploadFinalizeFieldsReadResult(
          status: UploadFinalizeFieldsReadStatus.failed,
        );
      }

      final fields = parseSubmissionTemplateFieldsFromJsMap(map);
      if (fields == null) {
        debugPrint('Fields is not a Map: ${map['fields']}');
        return const UploadFinalizeFieldsReadResult(
          status: UploadFinalizeFieldsReadStatus.failed,
        );
      }

      return UploadFinalizeFieldsReadResult(
        status: UploadFinalizeFieldsReadStatus.read,
        fields: fields,
      );
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
        source: buildApplySubmissionTemplateScript(fields),
      );
      final map = _decoder.decodeMap(raw);
      if (map == null || map['ok'] != true) {
        return const UploadTemplateApplyResult(
          status: UploadTemplateApplyStatus.failed,
        );
      }

      final failed = map['failed'] is List
          ? (map['failed'] as List).whereType<String>().toList()
          : <String>[];
      if (failed.isNotEmpty) {
        return UploadTemplateApplyResult(
          status: UploadTemplateApplyStatus.partiallyApplied,
          failedFields: List<String>.unmodifiable(failed),
        );
      }

      return const UploadTemplateApplyResult(
        status: UploadTemplateApplyStatus.applied,
      );
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
      source: buildUploadFilePickerHandlerScript(),
    );
  }

  Future<void> injectFile(UploadSelectedFile selectedFile) async {
    await _controller!.evaluateJavascript(
      source: buildUploadFileInputScript(
        base64Data: selectedFile.base64Data,
        fileName: selectedFile.fileName,
        extension: selectedFile.extension,
        returnResult: false,
      ),
    );
  }
}
