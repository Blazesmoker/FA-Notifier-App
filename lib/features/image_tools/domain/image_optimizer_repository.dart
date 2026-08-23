import 'dart:typed_data';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';

abstract interface class ImageOptimizerRepository {
  Future<ImageInspection> inspect(Uint8List bytes, String fileName);

  Future<Uint8List> extractFrame(Uint8List bytes, int frameIndex);

  Future<ImageOptimizationResult> optimize({
    required Uint8List originalBytes,
    required String originalFileName,
    required ImageInspection inspection,
    required ImageOptimizationOptions options,
    required ImageOptimizationConstraints constraints,
  });

  Future<ImageOptimizationResult> preview({
    required Uint8List originalBytes,
    required String originalFileName,
    required ImageInspection inspection,
    required ImageOptimizationOptions options,
    required ImageOptimizationConstraints constraints,
  });

  void cancelPreview();

  Future<bool> saveCopy(ImageOptimizationResult result);
}
