import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class UploadPermissionService {
  const UploadPermissionService();

  Future<void> requestInitialPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.photos,
      ].request();
    }
  }
}
