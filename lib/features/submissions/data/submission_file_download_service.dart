import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'package:fanotifier/features/submissions/data/submission_cookie_service.dart';
import 'package:fanotifier/features/submissions/data/submission_url.dart';
import 'package:fanotifier/features/submissions/domain/submission_file_download_result.dart';
import 'package:fanotifier/features/submissions/domain/submission_attachment.dart';

class SubmissionFileDownloadService {
  const SubmissionFileDownloadService({
    required this._cookieService,
  });

  final SubmissionCookieService _cookieService;

  static const MethodChannel _filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );

  Future<SubmissionFileDownloadResult> download({
    required SubmissionAttachment attachment,
    required bool sfwEnabled,
    required bool nsfwAllowed,
  }) async {
    try {
      final downloadUrl = attachment.downloadUrl ?? attachment.contentUrl;
      if (!isTrustedSubmissionUrl(downloadUrl)) {
        return const SubmissionFileDownloadResult(
          SubmissionFileDownloadStatus.failed,
        );
      }
      final response = await _cookieService.getMediaWithSfwCookie(
        url: downloadUrl,
        sfwEnabled: sfwEnabled,
        nsfwAllowed: nsfwAllowed,
        additionalHeaders: const <String, String>{'Accept': '*/*'},
        timeout: const Duration(minutes: 2),
      );
      if (response.statusCode != 200) {
        return SubmissionFileDownloadResult(
          SubmissionFileDownloadStatus.httpFailure,
          statusCode: response.statusCode,
        );
      }
      final contentType =
          response.headers['content-type']?.trim().toLowerCase() ?? '';
      if (response.bodyBytes.isEmpty ||
          contentType.contains('text/html') ||
          contentType.contains('application/xhtml')) {
        return const SubmissionFileDownloadResult(
          SubmissionFileDownloadStatus.failed,
        );
      }

      final savedPath = await _saveFile(
        attachment: attachment,
        bytes: response.bodyBytes,
      );
      if (savedPath == null) {
        return const SubmissionFileDownloadResult(
          SubmissionFileDownloadStatus.cancelled,
        );
      }
      return const SubmissionFileDownloadResult(
        SubmissionFileDownloadStatus.saved,
      );
    } catch (_) {
      return const SubmissionFileDownloadResult(
        SubmissionFileDownloadStatus.failed,
      );
    }
  }

  Future<Uri?> _saveFile({
    required SubmissionAttachment attachment,
    required Uint8List bytes,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final savedPath = await _filePickerChannel.invokeMethod<String>(
        'save',
        <String, Object?>{
          'fileName': attachment.fileName,
          'fileType': FileType.custom.name,
          'initialDirectory': null,
          'allowedExtensions': <String>[attachment.extension],
          'bytes': bytes,
        },
      );
      if (savedPath == null) return null;
      return Uri.tryParse(savedPath) ?? Uri.file(savedPath);
    }
    return FilePicker.saveFile(
      dialogTitle: 'Save submission file',
      fileName: attachment.fileName,
      type: FileType.custom,
      allowedExtensions: <String>[attachment.extension],
      bytes: bytes,
    );
  }
}
