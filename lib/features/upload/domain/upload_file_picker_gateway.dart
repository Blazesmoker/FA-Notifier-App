import 'package:FANotifier/features/upload/domain/upload_selected_file.dart';

abstract interface class UploadFilePickerGateway {
  Future<UploadSelectedFile?> pickFile();

  Future<UploadSelectedFile?> pickGalleryImage();
}
