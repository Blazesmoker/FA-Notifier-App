import 'dart:typed_data';

import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';

class FaUploadFile {
  const FaUploadFile({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

class FaProfileBannerSnapshot {
  FaProfileBannerSnapshot({
    required this.actionUri,
    required Map<String, String> payload,
    required this.currentBannerUri,
    required this.removeActionUri,
    required Map<String, String> removePayload,
  })  : payload = Map<String, String>.unmodifiable(payload),
        removePayload = Map<String, String>.unmodifiable(removePayload);

  final Uri actionUri;
  final Map<String, String> payload;
  final Uri? currentBannerUri;
  final Uri? removeActionUri;
  final Map<String, String> removePayload;

  bool get canRemove =>
      currentBannerUri != null &&
      removeActionUri != null &&
      removePayload.containsKey('action-remove');
}

class FaAvatarGalleryItem {
  const FaAvatarGalleryItem({
    required this.id,
    required this.imageUri,
    required this.chooseUri,
    this.removeUri,
  });

  final String id;
  final Uri imageUri;
  final Uri chooseUri;
  final Uri? removeUri;
}

class FaAvatarManagementSnapshot {
  FaAvatarManagementSnapshot({
    required this.actionUri,
    required Map<String, String> payload,
    required this.currentAvatarUri,
    required List<FaAvatarGalleryItem> gallery,
  })  : payload = Map<String, String>.unmodifiable(payload),
        gallery = List<FaAvatarGalleryItem>.unmodifiable(gallery);

  final Uri actionUri;
  final Map<String, String> payload;
  final Uri? currentAvatarUri;
  final List<FaAvatarGalleryItem> gallery;
}

class FaProfileInfoSnapshot {
  const FaProfileInfoSnapshot(this.form);

  final FaSettingsFormSnapshot form;
}
