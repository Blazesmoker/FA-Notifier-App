import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';
import 'package:fanotifier/features/image_tools/domain/image_optimizer_repository.dart';
import 'package:fanotifier/shared/platform/image_export_service.dart';

const _minimumAutomaticJpegQuality = 70;
const _minimumAutomaticGifColors = 32;
const _minimumAutomaticLinearScale = 0.5;
const _automaticResizeStep = 0.95;
const _automaticFailureMessage =
    'Automatic optimization stopped because making this image fit would reduce it below an acceptable quality. Nothing was saved and your original is unchanged. Try cropping more, choosing JPG in Advanced settings, or selecting another image.';

class ImageOptimizerRepositoryImpl implements ImageOptimizerRepository {
  ImageOptimizerRepositoryImpl([
    this._exportService = const ImageExportService(),
  ]);

  final ImageExportService _exportService;
  Isolate? _previewIsolate;
  ReceivePort? _previewPort;
  int _previewGeneration = 0;

  @override
  Future<ImageInspection> inspect(Uint8List bytes, String fileName) {
    return Isolate.run(() => _inspect(bytes, fileName));
  }

  @override
  Future<Uint8List> extractFrame(Uint8List bytes, int frameIndex) {
    return Isolate.run(() => _extractFrame(bytes, frameIndex));
  }

  @override
  Future<ImageOptimizationResult> optimize({
    required Uint8List originalBytes,
    required String originalFileName,
    required ImageInspection inspection,
    required ImageOptimizationOptions options,
    required ImageOptimizationConstraints constraints,
  }) {
    if (_canUseNativeJpeg(inspection, options)) {
      return _optimizeNativeJpeg(
        originalBytes: originalBytes,
        originalFileName: originalFileName,
        inspection: inspection,
        options: options,
        constraints: constraints,
        enforceLimits: true,
      );
    }
    return Isolate.run(
      () => _optimize(
        originalBytes,
        originalFileName,
        inspection,
        options,
        constraints,
        true,
      ),
    );
  }

  @override
  Future<ImageOptimizationResult> preview({
    required Uint8List originalBytes,
    required String originalFileName,
    required ImageInspection inspection,
    required ImageOptimizationOptions options,
    required ImageOptimizationConstraints constraints,
  }) {
    cancelPreview();
    if (_canUseNativeJpeg(inspection, options)) {
      return _optimizeNativeJpeg(
        originalBytes: originalBytes,
        originalFileName: originalFileName,
        inspection: inspection,
        options: options,
        constraints: constraints,
        enforceLimits: true,
      );
    }
    final generation = ++_previewGeneration;
    final port = ReceivePort();
    _previewPort = port;
    return _runPreviewIsolate(
      generation: generation,
      port: port,
      request: (
        sendPort: port.sendPort,
        originalBytes: originalBytes,
        originalFileName: originalFileName,
        inspection: inspection,
        options: options,
        constraints: constraints,
      ),
    );
  }

  Future<ImageOptimizationResult> _runPreviewIsolate({
    required int generation,
    required ReceivePort port,
    required _PreviewIsolateRequest request,
  }) async {
    final isolate = await Isolate.spawn(_previewIsolateEntryPoint, request);
    if (generation != _previewGeneration) {
      isolate.kill(priority: Isolate.immediate);
      port.close();
      throw const ImagePreviewCancelledException();
    }
    _previewIsolate = isolate;
    try {
      late final Object? response;
      try {
        response = await port.first;
      } on StateError {
        throw const ImagePreviewCancelledException();
      }
      if (generation != _previewGeneration) {
        throw const ImagePreviewCancelledException();
      }
      if (response case (ImageOptimizationResult result, null, _)) return result;
      if (response case (null, String message, bool formatError)) {
        if (formatError) throw FormatException(message);
        throw Exception(message);
      }
      throw StateError('Image preview returned an invalid response.');
    } finally {
      if (generation == _previewGeneration) {
        _previewIsolate = null;
        _previewPort = null;
      }
      isolate.kill(priority: Isolate.immediate);
      port.close();
    }
  }

  @override
  void cancelPreview() {
    _previewGeneration++;
    _previewIsolate?.kill(priority: Isolate.immediate);
    _previewIsolate = null;
    _previewPort?.close();
    _previewPort = null;
  }

  Future<ImageOptimizationResult> _optimizeNativeJpeg({
    required Uint8List originalBytes,
    required String originalFileName,
    required ImageInspection inspection,
    required ImageOptimizationOptions options,
    required ImageOptimizationConstraints constraints,
    required bool enforceLimits,
  }) async {
    if (inspection.width == options.width &&
        inspection.height == options.height &&
        inspection.format == options.outputFormat &&
        _meetsLimits(
          inspection.width,
          inspection.height,
          originalBytes.lengthInBytes,
          constraints,
        )) {
      return ImageOptimizationResult(
        bytes: Uint8List.fromList(originalBytes),
        fileName: _outputName(originalFileName, ImageOutputFormat.jpeg),
        width: inspection.width,
        height: inspection.height,
        frameCount: 1,
        format: ImageOutputFormat.jpeg,
        lossless: true,
      );
    }
    var width = options.width;
    var height = options.height;

    Future<Uint8List> compress(int candidateQuality) async {
      final bytes = await FlutterImageCompress.compressWithList(
        originalBytes,
        minWidth: width,
        minHeight: height,
        quality: candidateQuality,
        format: CompressFormat.jpeg,
        autoCorrectionAngle: true,
      );
      if (bytes.isEmpty) {
        throw const FormatException('Native image compression failed.');
      }
      return bytes;
    }

    var encoded = await compress(100);
    final maxBytes = constraints.maxBytes;
    if (maxBytes != null && encoded.lengthInBytes > maxBytes) {
      encoded = await compress(_minimumAutomaticJpegQuality);
      final minimumWidth = math.max(
        1,
        (options.width * _minimumAutomaticLinearScale).round(),
      );
      final minimumHeight = math.max(
        1,
        (options.height * _minimumAutomaticLinearScale).round(),
      );
      while (encoded.lengthInBytes > maxBytes &&
          (width > minimumWidth || height > minimumHeight)) {
        final nextWidth = math.max(
          minimumWidth,
          (width * _automaticResizeStep).floor(),
        );
        final nextHeight = math.max(
          minimumHeight,
          (height * _automaticResizeStep).floor(),
        );
        if (nextWidth == width && nextHeight == height) break;
        width = nextWidth;
        height = nextHeight;
        encoded = await compress(_minimumAutomaticJpegQuality);
      }
      if (encoded.lengthInBytes <= maxBytes) {
        var low = _minimumAutomaticJpegQuality + 1;
        var high = 100;
        while (low <= high) {
          final candidateQuality = (low + high) ~/ 2;
          final candidate = await FlutterImageCompress.compressWithList(
            originalBytes,
            minWidth: width,
            minHeight: height,
            quality: candidateQuality,
            format: CompressFormat.jpeg,
            autoCorrectionAngle: true,
          );
          if (candidate.isNotEmpty && candidate.lengthInBytes <= maxBytes) {
            encoded = candidate;
            low = candidateQuality + 1;
          } else {
            high = candidateQuality - 1;
          }
        }
      }
    }
    final resultInspection = await inspect(encoded, 'result.jpg');
    if (enforceLimits &&
        !_meetsLimits(
          resultInspection.width,
          resultInspection.height,
          encoded.lengthInBytes,
          constraints,
        )) {
      throw const FormatException(_automaticFailureMessage);
    }
    return ImageOptimizationResult(
      bytes: Uint8List.fromList(encoded),
      fileName: _outputName(originalFileName, ImageOutputFormat.jpeg),
      width: resultInspection.width,
      height: resultInspection.height,
      frameCount: 1,
      format: ImageOutputFormat.jpeg,
      lossless: false,
    );
  }

  @override
  Future<bool> saveCopy(ImageOptimizationResult result) async {
    final permitted = await _exportService.requestImageExportPermission();
    if (!permitted) return false;
    return _exportService.saveImageToGallery(
      result.bytes,
      quality: 100,
      fileName: result.fileName,
      androidRelativePath: 'Pictures/FANotifier/Optimized',
      skipIfExists: false,
    );
  }
}

typedef _PreviewIsolateRequest = ({
  SendPort sendPort,
  Uint8List originalBytes,
  String originalFileName,
  ImageInspection inspection,
  ImageOptimizationOptions options,
  ImageOptimizationConstraints constraints,
});

void _previewIsolateEntryPoint(_PreviewIsolateRequest request) {
  try {
    final result = _optimize(
      request.originalBytes,
      request.originalFileName,
      request.inspection,
      request.options,
      request.constraints,
      true,
    );
    request.sendPort.send((result, null, false));
  } catch (error) {
    final message = error is FormatException ? error.message : '$error';
    final formatError = error is FormatException;
    request.sendPort.send((null, message, formatError));
  }
}

bool _canUseNativeJpeg(
  ImageInspection inspection,
  ImageOptimizationOptions options,
) {
  if (inspection.animated || options.outputFormat != ImageOutputFormat.jpeg) {
    return false;
  }
  if (options.resizeMode != ImageResizeMode.fit ||
      options.width > inspection.width ||
      options.height > inspection.height) {
    return false;
  }
  final sourceRatio = inspection.width / inspection.height;
  final targetRatio = options.width / options.height;
  return (sourceRatio - targetRatio).abs() < 0.01;
}

ImageInspection _inspect(Uint8List bytes, String fileName) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('This image could not be decoded.');
  }
  return ImageInspection(
    width: decoded.width,
    height: decoded.height,
    byteLength: bytes.lengthInBytes,
    frameCount: decoded.numFrames,
    format: _formatFromNameAndBytes(fileName, bytes),
  );
}

ImageOptimizationResult _optimize(
  Uint8List originalBytes,
  String originalFileName,
  ImageInspection inspection,
  ImageOptimizationOptions options,
  ImageOptimizationConstraints constraints,
  bool enforceLimits,
) {
  if (inspection.animated &&
      options.outputFormat != ImageOutputFormat.gif &&
      options.frameIndex == null) {
    throw const FormatException('Animated images must stay in GIF format.');
  }
  final unchanged = inspection.width == options.width &&
      inspection.height == options.height &&
      inspection.format == options.outputFormat &&
      options.resizeMode != ImageResizeMode.crop &&
      options.frameIndex == null &&
      _meetsLimits(
        inspection.width,
        inspection.height,
        originalBytes.lengthInBytes,
        constraints,
      );
  if (unchanged) {
    return ImageOptimizationResult(
      bytes: Uint8List.fromList(originalBytes),
      fileName: _outputName(originalFileName, options.outputFormat),
      width: inspection.width,
      height: inspection.height,
      frameCount: inspection.frameCount,
      format: options.outputFormat,
      lossless: true,
    );
  }

  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) {
    throw const FormatException('This image could not be decoded.');
  }
  var source = decoded;
  if (options.frameIndex != null) {
    source = img.Image.from(
      decoded.getFrame(
        options.frameIndex!.clamp(0, decoded.numFrames - 1).toInt(),
      ),
      noAnimation: true,
    ).convert(numChannels: 4);
    if (options.outputFormat == ImageOutputFormat.jpeg) {
      source.backgroundColor = img.ColorRgb8(0, 0, 0);
    }
  }
  var width = math.max(1, options.width);
  var height = math.max(1, options.height);
  var transformed = _resize(
    source,
    width,
    height,
    options.resizeMode,
    options.cropRegion,
  );
  var encoded = _encode(transformed, options.outputFormat, 100, 256);

  final maxBytes = constraints.maxBytes;
  if (maxBytes != null && encoded.lengthInBytes > maxBytes) {
    if (options.outputFormat == ImageOutputFormat.jpeg) {
      final best = _bestJpegEncoding(transformed, maxBytes);
      encoded = best.bytes;
    } else if (options.outputFormat == ImageOutputFormat.gif) {
      final best = _bestGifEncoding(transformed, maxBytes);
      encoded = best.bytes;
    }
    final minimumWidth = math.max(
      1,
      (options.width * _minimumAutomaticLinearScale).round(),
    );
    final minimumHeight = math.max(
      1,
      (options.height * _minimumAutomaticLinearScale).round(),
    );
    while (encoded.lengthInBytes > maxBytes &&
        (width > minimumWidth || height > minimumHeight)) {
      final nextWidth = math.max(
        minimumWidth,
        (width * _automaticResizeStep).floor(),
      );
      final nextHeight = math.max(
        minimumHeight,
        (height * _automaticResizeStep).floor(),
      );
      if (nextWidth == width && nextHeight == height) break;
      width = nextWidth;
      height = nextHeight;
      transformed = _resize(
        source,
        width,
        height,
        options.resizeMode,
        options.cropRegion,
      );
      encoded = _encode(
        transformed,
        options.outputFormat,
        options.outputFormat == ImageOutputFormat.jpeg
            ? _minimumAutomaticJpegQuality
            : 100,
        options.outputFormat == ImageOutputFormat.gif
            ? _minimumAutomaticGifColors
            : 256,
      );
    }
    if (encoded.lengthInBytes <= maxBytes) {
      if (options.outputFormat == ImageOutputFormat.jpeg) {
        final best = _bestJpegEncoding(transformed, maxBytes);
        encoded = best.bytes;
      } else if (options.outputFormat == ImageOutputFormat.gif) {
        final best = _bestGifEncoding(transformed, maxBytes);
        encoded = best.bytes;
      }
    }
  }

  if (enforceLimits &&
      !_meetsLimits(width, height, encoded.lengthInBytes, constraints)) {
    throw const FormatException(_automaticFailureMessage);
  }
  return ImageOptimizationResult(
    bytes: encoded,
    fileName: _outputName(originalFileName, options.outputFormat),
    width: width,
    height: height,
    frameCount: transformed.numFrames,
    format: options.outputFormat,
    lossless: false,
  );
}

Uint8List _extractFrame(Uint8List bytes, int frameIndex) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('This image could not be decoded.');
  }
  final index = frameIndex.clamp(0, decoded.numFrames - 1).toInt();
  final frame = img.Image.from(decoded.getFrame(index), noAnimation: true);
  return img.encodePng(frame, level: 1);
}

img.Image _resize(
  img.Image source,
  int width,
  int height,
  ImageResizeMode mode,
  ImageCropRegion? cropRegion,
) {
  if (mode == ImageResizeMode.crop) {
    final region = cropRegion ?? const ImageCropRegion();
    if (region.hasFreeformBounds) {
      final left = region.left!.clamp(0.0, 1.0).toDouble();
      final top = region.top!.clamp(0.0, 1.0).toDouble();
      final right = region.right!.clamp(left, 1.0).toDouble();
      final bottom = region.bottom!.clamp(top, 1.0).toDouble();
      final cropX = (left * source.width)
          .floor()
          .clamp(0, source.width - 1)
          .toInt();
      final cropY = (top * source.height)
          .floor()
          .clamp(0, source.height - 1)
          .toInt();
      final cropRight = (right * source.width)
          .ceil()
          .clamp(cropX + 1, source.width)
          .toInt();
      final cropBottom = (bottom * source.height)
          .ceil()
          .clamp(cropY + 1, source.height)
          .toInt();
      final cropped = img.copyCrop(
        source,
        x: cropX,
        y: cropY,
        width: cropRight - cropX,
        height: cropBottom - cropY,
      );
      if (cropped.width == width && cropped.height == height) return cropped;
      return img.copyResize(
        cropped,
        width: width,
        height: height,
        maintainAspect: true,
        interpolation: _resizeInterpolation(
          cropped.width,
          cropped.height,
          width,
          height,
        ),
      );
    }
    final sourceRatio = source.width / source.height;
    final targetRatio = width / height;
    late double baseCropWidth;
    late double baseCropHeight;
    if (sourceRatio > targetRatio) {
      baseCropWidth = source.height * targetRatio;
      baseCropHeight = source.height.toDouble();
    } else {
      baseCropWidth = source.width.toDouble();
      baseCropHeight = source.width / targetRatio;
    }
    final zoom = region.zoom.clamp(1.0, 6.0).toDouble();
    final cropWidth = math.max(1, (baseCropWidth / zoom).round()).toInt();
    final cropHeight = math.max(1, (baseCropHeight / zoom).round()).toInt();
    final centerX = (region.centerX.clamp(0.0, 1.0) * source.width)
        .clamp(cropWidth / 2, source.width - cropWidth / 2)
        .toDouble();
    final centerY = (region.centerY.clamp(0.0, 1.0) * source.height)
        .clamp(cropHeight / 2, source.height - cropHeight / 2)
        .toDouble();
    final cropX = (centerX - cropWidth / 2)
        .round()
        .clamp(0, source.width - cropWidth)
        .toInt();
    final cropY = (centerY - cropHeight / 2)
        .round()
        .clamp(0, source.height - cropHeight)
        .toInt();
    final cropped = img.copyCrop(
      source,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );
    return img.copyResize(
      cropped,
      width: width,
      height: height,
      interpolation: _resizeInterpolation(
        cropped.width,
        cropped.height,
        width,
        height,
      ),
    );
  }
  return img.copyResize(
    source,
    width: width,
    height: height,
    maintainAspect: mode == ImageResizeMode.fit,
    interpolation: _resizeInterpolation(
      source.width,
      source.height,
      width,
      height,
    ),
  );
}

img.Interpolation _resizeInterpolation(
  int sourceWidth,
  int sourceHeight,
  int outputWidth,
  int outputHeight,
) {
  return outputWidth > sourceWidth || outputHeight > sourceHeight
      ? img.Interpolation.nearest
      : img.Interpolation.average;
}

({Uint8List bytes, int quality}) _bestJpegEncoding(
  img.Image image,
  int maxBytes,
) {
  final fullQuality = img.encodeJpg(image, quality: 100);
  if (fullQuality.lengthInBytes <= maxBytes) {
    return (bytes: fullQuality, quality: 100);
  }
  var quality = _minimumAutomaticJpegQuality;
  var bytes = img.encodeJpg(image, quality: quality);
  if (bytes.lengthInBytes > maxBytes) {
    return (bytes: bytes, quality: quality);
  }
  var low = quality + 1;
  var high = 99;
  while (low <= high) {
    final candidateQuality = (low + high) ~/ 2;
    final candidate = img.encodeJpg(image, quality: candidateQuality);
    if (candidate.lengthInBytes <= maxBytes) {
      quality = candidateQuality;
      bytes = candidate;
      low = candidateQuality + 1;
    } else {
      high = candidateQuality - 1;
    }
  }
  return (bytes: bytes, quality: quality);
}

({Uint8List bytes, int colors}) _bestGifEncoding(
  img.Image image,
  int maxBytes,
) {
  const candidates = [256, 128, 64, _minimumAutomaticGifColors];
  late Uint8List bytes;
  var colors = _minimumAutomaticGifColors;
  for (final candidateColors in candidates) {
    final candidate = _encode(
      image,
      ImageOutputFormat.gif,
      100,
      candidateColors,
    );
    bytes = candidate;
    colors = candidateColors;
    if (candidate.lengthInBytes <= maxBytes) break;
  }
  return (bytes: bytes, colors: colors);
}

Uint8List _encode(
  img.Image image,
  ImageOutputFormat format,
  int quality,
  int gifColors,
) {
  return switch (format) {
    ImageOutputFormat.jpeg => img.encodeJpg(image, quality: quality),
    ImageOutputFormat.png => img.encodePng(image, level: 9),
    ImageOutputFormat.gif => img.GifEncoder(numColors: gifColors).encode(
        gifColors < 256 ? image.convert(numChannels: 4) : image,
      ),
  };
}

bool _meetsLimits(
  int width,
  int height,
  int byteLength,
  ImageOptimizationConstraints constraints,
) {
  if (constraints.maxBytes != null && byteLength > constraints.maxBytes!) {
    return false;
  }
  if (constraints.maxWidth != null && width > constraints.maxWidth!) {
    return false;
  }
  if (constraints.maxHeight != null && height > constraints.maxHeight!) {
    return false;
  }
  if (constraints.maxMegapixels != null &&
      (width * height) / 1000000 > constraints.maxMegapixels!) {
    return false;
  }
  return true;
}

ImageOutputFormat _formatFromNameAndBytes(String fileName, Uint8List bytes) {
  final extension = fileName.split('.').last.toLowerCase();
  if (extension == 'gif' ||
      (bytes.length > 3 &&
          bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46)) {
    return ImageOutputFormat.gif;
  }
  if (extension == 'png' ||
      (bytes.length > 3 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e)) {
    return ImageOutputFormat.png;
  }
  return ImageOutputFormat.jpeg;
}

String _outputName(String originalName, ImageOutputFormat format) {
  final dot = originalName.lastIndexOf('.');
  final base = dot > 0 ? originalName.substring(0, dot) : originalName;
  final safeBase = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return '${safeBase}_optimized_${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
}
