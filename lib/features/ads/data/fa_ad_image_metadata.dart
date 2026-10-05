import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';

Future<FaAdSize> readFaAdImageSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 || descriptor.height <= 0) {
      throw const FaAdFailure(FaAdFailureReason.invalidResponse);
    }
    return FaAdSize(descriptor.width, descriptor.height);
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}
