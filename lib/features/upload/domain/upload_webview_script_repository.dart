import 'package:fanotifier/features/upload/domain/submission_template.dart';
import 'package:fanotifier/features/upload/domain/upload_selected_file.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_results.dart';

abstract interface class UploadWebViewScriptRepository {
  String buildWrapSelectionScript(String tag);

  String buildInitialPageScript({required bool isIOS});

  String buildFinalizePageScript({required bool isIOS});

  String buildClearFinalizeFormScript();

  String buildReadTemplateFieldsScript();

  String buildApplyTemplateScript(SubmissionTemplateFields fields);

  String buildFilePickerHandlerScript();

  String buildFileInputScript(
    UploadSelectedFile selectedFile, {
    required String inputName,
  });

  UploadClearFormResult decodeClearFormResult(Object? result);

  UploadFinalizeFieldsReadResult decodeFinalizeFieldsReadResult(
    Object? result,
  );

  UploadTemplateApplyResult decodeTemplateApplyResult(Object? result);
}
