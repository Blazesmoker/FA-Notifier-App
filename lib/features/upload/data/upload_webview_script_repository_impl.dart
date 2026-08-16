import 'package:fanotifier/features/upload/data/upload_file_webview_scripts.dart'
    as file_scripts;
import 'package:fanotifier/features/upload/data/upload_js_result_decoder.dart';
import 'package:fanotifier/features/upload/data/upload_page_webview_scripts.dart'
    as page_scripts;
import 'package:fanotifier/features/upload/data/upload_template_js_builder.dart'
    as template_scripts;
import 'package:fanotifier/features/upload/domain/submission_template.dart';
import 'package:fanotifier/features/upload/domain/upload_selected_file.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_script_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_results.dart';
import 'package:flutter/foundation.dart';

class UploadWebViewScriptRepositoryImpl
    implements UploadWebViewScriptRepository {
  const UploadWebViewScriptRepositoryImpl({
    this._decoder = const UploadJsResultDecoder(),
  });

  final UploadJsResultDecoder _decoder;

  @override
  String buildWrapSelectionScript(String tag) {
    return file_scripts.buildUploadWrapSelectionScript(tag);
  }

  @override
  String buildInitialPageScript({required bool isIOS}) {
    return page_scripts.buildUploadInitialPageScript(isIOS: isIOS);
  }

  @override
  String buildFinalizePageScript({required bool isIOS}) {
    return page_scripts.buildUploadFinalizePageScript(isIOS: isIOS);
  }

  @override
  String buildClearFinalizeFormScript() {
    return page_scripts.buildClearFinalizeFormScript();
  }

  @override
  String buildReadTemplateFieldsScript() {
    return template_scripts.buildReadSubmissionTemplateFieldsScript();
  }

  @override
  String buildApplyTemplateScript(SubmissionTemplateFields fields) {
    return template_scripts.buildApplySubmissionTemplateScript(fields);
  }

  @override
  String buildFilePickerHandlerScript() {
    return file_scripts.buildUploadFilePickerHandlerScript();
  }

  @override
  String buildFileInputScript(UploadSelectedFile selectedFile) {
    return file_scripts.buildUploadFileInputScript(
      base64Data: selectedFile.base64Data,
      fileName: selectedFile.fileName,
      extension: selectedFile.extension,
      returnResult: false,
    );
  }

  @override
  UploadClearFormResult decodeClearFormResult(Object? result) {
    final map = _decoder.decodeMap(result);
    if (map != null && map['ok'] == true) {
      return const UploadClearFormResult(UploadClearFormStatus.cleared);
    }
    return const UploadClearFormResult(UploadClearFormStatus.failed);
  }

  @override
  UploadFinalizeFieldsReadResult decodeFinalizeFieldsReadResult(
    Object? result,
  ) {
    final map = _decoder.decodeMap(result);
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

    final fields =
        template_scripts.parseSubmissionTemplateFieldsFromJsMap(map);
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
  }

  @override
  UploadTemplateApplyResult decodeTemplateApplyResult(Object? result) {
    final map = _decoder.decodeMap(result);
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
  }
}
