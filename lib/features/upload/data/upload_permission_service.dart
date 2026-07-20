import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import 'package:fanotifier/features/upload/domain/upload_permission_gateway.dart';

class UploadPermissionService implements UploadPermissionGateway {
  const UploadPermissionService();

  @override
  Future<void> requestInitialPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.photos,
      ].request();
    }
  }
}
