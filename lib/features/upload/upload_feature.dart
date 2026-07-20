import 'package:fanotifier/features/upload/data/submission_template_repository_impl.dart';
import 'package:fanotifier/features/upload/data/upload_file_picker_service.dart';
import 'package:fanotifier/features/upload/data/upload_permission_service.dart';
import 'package:fanotifier/features/upload/data/upload_submission_navigation_service.dart';
import 'package:fanotifier/features/upload/data/upload_webview_script_repository_impl.dart';
import 'package:fanotifier/features/upload/data/upload_webview_session_gateway_impl.dart';
import 'package:fanotifier/features/upload/domain/submission_template_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_file_picker_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_navigation_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_permission_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_script_repository.dart';
import 'package:fanotifier/features/upload/domain/upload_webview_session_gateway.dart';

class UploadFeature {
  const UploadFeature._();

  static UploadFilePickerGateway createFilePickerGateway() {
    return const UploadFilePickerService();
  }

  static UploadPermissionGateway createPermissionGateway() {
    return const UploadPermissionService();
  }

  static UploadNavigationRepository createNavigationRepository() {
    return const UploadSubmissionNavigationService();
  }

  static SubmissionTemplateRepository createTemplateRepository() {
    return SubmissionTemplateRepositoryImpl();
  }

  static UploadWebViewScriptRepository createWebViewScriptRepository() {
    return const UploadWebViewScriptRepositoryImpl();
  }

  static UploadWebViewSessionGateway createWebViewSessionGateway() {
    return const UploadWebViewSessionGatewayImpl();
  }
}
