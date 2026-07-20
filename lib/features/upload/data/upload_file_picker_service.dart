import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fanotifier/features/upload/domain/upload_file_picker_gateway.dart';
import 'package:fanotifier/features/upload/domain/upload_selected_file.dart';

class UploadFilePickerService implements UploadFilePickerGateway {
  const UploadFilePickerService();

  @override
  Future<UploadSelectedFile?> pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif'],
    );
    if (file == null) {
      return null;
    }

    final bytes = (await file.readAsBytes()).toList();
    return _createSelectedFile(fileName: file.name, bytes: bytes);
  }

  @override
  Future<UploadSelectedFile?> pickGalleryImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile == null) {
      return null;
    }

    final bytes = await File(pickedFile.path).readAsBytes();
    return _createSelectedFile(fileName: pickedFile.name, bytes: bytes);
  }

  UploadSelectedFile _createSelectedFile({
    required String fileName,
    required List<int> bytes,
  }) {
    return UploadSelectedFile(
      fileName: fileName,
      base64Data: base64Encode(bytes),
      extension: fileName.split('.').last.toLowerCase(),
    );
  }
}
