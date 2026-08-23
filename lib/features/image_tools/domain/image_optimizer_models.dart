import 'dart:typed_data';

enum ImageOutputFormat { jpeg, png, gif }

extension ImageOutputFormatDetails on ImageOutputFormat {
  String get label => switch (this) {
        ImageOutputFormat.jpeg => 'JPG',
        ImageOutputFormat.png => 'PNG',
        ImageOutputFormat.gif => 'GIF',
      };

  String get extension => switch (this) {
        ImageOutputFormat.jpeg => 'jpg',
        ImageOutputFormat.png => 'png',
        ImageOutputFormat.gif => 'gif',
      };

  String get mimeType => switch (this) {
        ImageOutputFormat.jpeg => 'image/jpeg',
        ImageOutputFormat.png => 'image/png',
        ImageOutputFormat.gif => 'image/gif',
      };
}

enum ImageResizeMode { fit, crop, stretch }

enum ImageSizeAccuracy { estimated, measuring, measured }

class ImageOptimizationConstraints {
  const ImageOptimizationConstraints({
    required this.title,
    required this.allowedFormats,
    this.maxBytes,
    this.maxWidth,
    this.maxHeight,
    this.maxMegapixels,
    this.maxMegapixelEquivalentWidth,
    this.maxMegapixelEquivalentHeight,
    this.preferredFormat,
    this.siteConvertsToJpeg = false,
    this.cropAspectRatio,
    this.allowAnimatedFrameSelection = false,
    this.allowStretch = false,
  });

  final String title;
  final Set<ImageOutputFormat> allowedFormats;
  final int? maxBytes;
  final int? maxWidth;
  final int? maxHeight;
  final double? maxMegapixels;
  final int? maxMegapixelEquivalentWidth;
  final int? maxMegapixelEquivalentHeight;
  final ImageOutputFormat? preferredFormat;
  final bool siteConvertsToJpeg;
  final double? cropAspectRatio;
  final bool allowAnimatedFrameSelection;
  final bool allowStretch;

  bool accepts({
    required int width,
    required int height,
    required int byteLength,
  }) {
    if (maxBytes != null && byteLength > maxBytes!) return false;
    if (maxWidth != null && width > maxWidth!) return false;
    if (maxHeight != null && height > maxHeight!) return false;
    if (maxMegapixels != null &&
        width * height / 1000000 > maxMegapixels!) {
      return false;
    }
    return true;
  }
}

class ImagePreviewCancelledException implements Exception {
  const ImagePreviewCancelledException();
}

class ImageCropRegion {
  const ImageCropRegion({
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.zoom = 1,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });

  final double centerX;
  final double centerY;
  final double zoom;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;

  bool get hasFreeformBounds =>
      left != null && top != null && right != null && bottom != null;

  @override
  bool operator ==(Object other) {
    return other is ImageCropRegion &&
        other.centerX == centerX &&
        other.centerY == centerY &&
        other.zoom == zoom &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(
        centerX,
        centerY,
        zoom,
        left,
        top,
        right,
        bottom,
      );
}

class ImageSizeEstimate {
  const ImageSizeEstimate({
    required this.byteLength,
    required this.accuracy,
  });

  final int byteLength;
  final ImageSizeAccuracy accuracy;
}

class ImageInspection {
  const ImageInspection({
    required this.width,
    required this.height,
    required this.byteLength,
    required this.frameCount,
    required this.format,
  });

  final int width;
  final int height;
  final int byteLength;
  final int frameCount;
  final ImageOutputFormat format;

  bool get animated => frameCount > 1;
}

class ImageOptimizationOptions {
  const ImageOptimizationOptions({
    required this.width,
    required this.height,
    required this.resizeMode,
    required this.outputFormat,
    this.cropRegion,
    this.frameIndex,
  });

  final int width;
  final int height;
  final ImageResizeMode resizeMode;
  final ImageOutputFormat outputFormat;
  final ImageCropRegion? cropRegion;
  final int? frameIndex;
}

class ImageOptimizationResult {
  const ImageOptimizationResult({
    required this.bytes,
    required this.fileName,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.format,
    required this.lossless,
  });

  final Uint8List bytes;
  final String fileName;
  final int width;
  final int height;
  final int frameCount;
  final ImageOutputFormat format;
  final bool lossless;

  int get byteLength => bytes.lengthInBytes;
}
