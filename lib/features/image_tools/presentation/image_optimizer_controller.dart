import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';
import 'package:fanotifier/features/image_tools/domain/image_optimizer_repository.dart';

class ImageOptimizerController extends ChangeNotifier {
  ImageOptimizerController({
    required this._repository,
    required this._originalBytes,
    required this._originalFileName,
    required this._constraints,
  });

  final ImageOptimizerRepository _repository;
  final Uint8List _originalBytes;
  final String _originalFileName;
  final ImageOptimizationConstraints _constraints;

  Timer? _previewTimer;
  int _previewGeneration = 0;
  int _frameGeneration = 0;
  bool _parameterAdjustmentActive = false;
  ImageCropRegion? _cropRegionBeforeAdjustment;
  bool _disposed = false;
  ImageOutputFormat? _defaultFormat;
  ImageResizeMode _defaultResizeMode = ImageResizeMode.fit;
  ImageInspection? inspection;
  ImageOptimizationResult? result;
  ImageOutputFormat? format;
  ImageResizeMode resizeMode = ImageResizeMode.fit;
  final ValueNotifier<ImageSizeEstimate?> sizeEstimateListenable =
      ValueNotifier(null);
  bool working = true;
  bool measuring = false;
  bool applyingParameters = false;
  bool resultCurrent = false;
  bool _optimizationFailed = false;
  bool advancedExpanded = false;
  int width = 1;
  int height = 1;
  ImageCropRegion cropRegion = const ImageCropRegion();
  Uint8List? selectedFrameBytes;
  int selectedFrameIndex = 0;
  bool frameLoading = false;
  String? error;

  ImageOptimizationConstraints get constraints => _constraints;
  ImageSizeEstimate? get sizeEstimate => sizeEstimateListenable.value;
  Uint8List get displaySourceBytes => selectedFrameBytes ?? _originalBytes;
  bool get selectsAnimatedFrame =>
      inspection?.animated == true && _constraints.allowAnimatedFrameSelection;

  bool get advancedSettingsChanged {
    final value = inspection;
    if (value == null) return false;
    final automaticSize = _automaticSize(value);
    return width != automaticSize.$1 ||
        height != automaticSize.$2 ||
        format != _defaultFormat;
  }

  bool get currentEstimateFits {
    final value = inspection;
    final estimate = sizeEstimate;
    if (value == null || estimate == null || _optimizationFailed) return false;
    final currentResult = resultCurrent ? result : null;
    return _constraints.accepts(
      width: currentResult?.width ?? width,
      height: currentResult?.height ?? height,
      byteLength: estimate.byteLength,
    );
  }

  bool get canSave =>
      !frameLoading && resultCurrent && result != null && currentEstimateFits;

  Future<void> initialize() async {
    try {
      final value = await _repository.inspect(_originalBytes, _originalFileName);
      if (_disposed) return;
      var selectedFormat = _constraints.preferredFormat ?? value.format;
      if (value.animated && !_constraints.allowAnimatedFrameSelection) {
        selectedFormat = ImageOutputFormat.gif;
      }
      if (!_constraints.allowedFormats.contains(selectedFormat)) {
        selectedFormat = _constraints.allowedFormats.first;
      }
      final initialSize = _initialSize(value);
      inspection = value;
      format = selectedFormat;
      if (_constraints.cropAspectRatio != null) {
        resizeMode = ImageResizeMode.crop;
      }
      width = initialSize.$1;
      height = initialSize.$2;
      _defaultFormat = format;
      _defaultResizeMode = resizeMode;
      if (value.animated && _constraints.allowAnimatedFrameSelection) {
        selectedFrameBytes = await _repository.extractFrame(_originalBytes, 0);
        if (_disposed) return;
      }
      working = false;
      _updateEstimate();
      notifyListeners();
      schedulePreview(immediate: true);
    } catch (exception) {
      if (_disposed) return;
      working = false;
      error = '$exception';
      notifyListeners();
    }
  }

  void setAdvancedExpanded(bool value) {
    advancedExpanded = value;
    notifyListeners();
  }

  void setDimensions(int newWidth, int newHeight) {
    width = math.max(1, newWidth);
    height = math.max(1, newHeight);
    _settingsChanged();
  }

  void setResizeMode(ImageResizeMode value) {
    if (value == ImageResizeMode.stretch && !_constraints.allowStretch) return;
    resizeMode = value;
    final valueInspection = inspection;
    if (valueInspection != null) {
      if (value == ImageResizeMode.crop &&
          _constraints.cropAspectRatio == null) {
        _updateFreeformCropSize(valueInspection);
      } else {
        final initialSize = _initialSize(valueInspection);
        width = initialSize.$1;
        height = initialSize.$2;
      }
    }
    _settingsChanged(immediate: true);
  }

  void setCropRegion(ImageCropRegion value) {
    cropRegion = value;
    final valueInspection = inspection;
    if (valueInspection != null &&
        resizeMode == ImageResizeMode.crop &&
        _constraints.cropAspectRatio == null) {
      _updateFreeformCropSize(valueInspection);
    }
    if (_parameterAdjustmentActive) {
      resultCurrent = false;
      error = null;
      _updateEstimate();
      notifyListeners();
      return;
    }
    _settingsChanged();
  }

  void beginCropAdjustment() {
    _cropRegionBeforeAdjustment = cropRegion;
    _beginParameterAdjustment();
  }

  void finishCropAdjustment() {
    if (!_parameterAdjustmentActive) return;
    _parameterAdjustmentActive = false;
    final changed = _cropRegionBeforeAdjustment != cropRegion;
    _cropRegionBeforeAdjustment = null;
    if (!changed) {
      notifyListeners();
      return;
    }
    applyingParameters = true;
    createPreview();
  }

  Future<void> setFrameIndex(int value) async {
    final source = inspection;
    if (source == null || !selectsAnimatedFrame) return;
    final next = value.clamp(0, source.frameCount - 1).toInt();
    if (next == selectedFrameIndex && selectedFrameBytes != null) return;
    final generation = ++_frameGeneration;
    selectedFrameIndex = next;
    frameLoading = true;
    applyingParameters = true;
    resultCurrent = false;
    _optimizationFailed = false;
    error = null;
    notifyListeners();
    try {
      final bytes = await _repository.extractFrame(_originalBytes, next);
      if (_disposed || generation != _frameGeneration) return;
      selectedFrameBytes = bytes;
      frameLoading = false;
      notifyListeners();
      schedulePreview(immediate: true);
    } catch (exception) {
      if (_disposed || generation != _frameGeneration) return;
      frameLoading = false;
      applyingParameters = false;
      error = '$exception';
      notifyListeners();
    }
  }

  void setFormat(ImageOutputFormat value) {
    format = value;
    _settingsChanged(immediate: true);
  }

  void _beginParameterAdjustment() {
    _previewTimer?.cancel();
    _previewGeneration++;
    _repository.cancelPreview();
    _parameterAdjustmentActive = true;
    measuring = false;
    applyingParameters = false;
    notifyListeners();
  }

  void resetAdvancedSettings() {
    final defaultFormat = _defaultFormat;
    final value = inspection;
    if (value == null || defaultFormat == null) return;
    format = defaultFormat;
    resizeMode = _defaultResizeMode;
    final automaticSize = _automaticSize(value);
    width = automaticSize.$1;
    height = automaticSize.$2;
    _settingsChanged(immediate: true);
  }

  void schedulePreview({bool immediate = false}) {
    final value = inspection;
    if (value == null || format == null || working) return;
    _previewTimer?.cancel();
    _repository.cancelPreview();
    if (value.animated && !_constraints.allowAnimatedFrameSelection && !immediate) {
      return;
    }
    final generation = ++_previewGeneration;
    final delay = immediate
        ? const Duration(milliseconds: 48)
        : const Duration(milliseconds: 350);
    measuring = true;
    _optimizationFailed = false;
    _setSizeEstimate(ImageSizeEstimate(
      byteLength: sizeEstimate?.byteLength ?? value.byteLength,
      accuracy: ImageSizeAccuracy.measuring,
    ));
    notifyListeners();
    _previewTimer = Timer(delay, () => _measurePreview(generation));
  }

  Future<void> createPreview() async {
    _previewTimer?.cancel();
    _repository.cancelPreview();
    final generation = ++_previewGeneration;
    measuring = true;
    _optimizationFailed = false;
    error = null;
    notifyListeners();
    await _measurePreview(generation);
  }

  Future<bool> saveCopy() async {
    final value = result;
    if (!canSave || value == null || working) return false;
    working = true;
    error = null;
    notifyListeners();
    try {
      final saved = await _repository.saveCopy(value);
      if (_disposed) return false;
      if (saved) return true;
      working = false;
      error = 'The changed copy could not be saved. The original was not modified.';
      notifyListeners();
    } catch (exception) {
      if (_disposed) return false;
      working = false;
      error = '$exception';
      notifyListeners();
    }
    return false;
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void _settingsChanged({bool immediate = false}) {
    resultCurrent = false;
    applyingParameters = true;
    _optimizationFailed = false;
    error = null;
    _updateEstimate();
    notifyListeners();
    schedulePreview(immediate: immediate);
  }

  void _updateEstimate() {
    final value = inspection;
    final selectedFormat = format;
    if (value == null || selectedFormat == null) return;
    final sourcePixels = math.max(1, value.width * value.height);
    final targetPixels = math.max(1, width * height);
    final pixelFactor = targetPixels / sourcePixels;
    var formatFactor = 1.0;
    if (selectedFormat == ImageOutputFormat.jpeg) {
      formatFactor = value.format == ImageOutputFormat.jpeg
          ? 1
          : 0.72;
    } else if (selectedFormat == ImageOutputFormat.gif) {
      formatFactor = value.format == ImageOutputFormat.gif
          ? 1
          : 0.9;
    } else if (value.format != ImageOutputFormat.png) {
      formatFactor = 1.35;
    }
    final estimated = math.max(
      1,
      (value.byteLength * pixelFactor * formatFactor).round(),
    );
    _setSizeEstimate(ImageSizeEstimate(
      byteLength: estimated,
      accuracy: ImageSizeAccuracy.estimated,
    ));
  }

  Future<void> _measurePreview(int generation) async {
    final value = inspection;
    final selectedFormat = format;
    if (value == null || selectedFormat == null) return;
    final options = ImageOptimizationOptions(
      width: width,
      height: height,
      resizeMode: resizeMode,
      outputFormat: selectedFormat,
      cropRegion: cropRegion,
      frameIndex: selectsAnimatedFrame ? selectedFrameIndex : null,
    );
    try {
      final preview = await _repository.preview(
        originalBytes: _originalBytes,
        originalFileName: _originalFileName,
        inspection: value,
        options: options,
        constraints: _constraints,
      );
      if (generation != _previewGeneration) return;
      result = preview;
      resultCurrent = true;
      _optimizationFailed = false;
      measuring = false;
      applyingParameters = false;
      _setSizeEstimate(ImageSizeEstimate(
        byteLength: preview.byteLength,
        accuracy: ImageSizeAccuracy.measured,
      ));
      notifyListeners();
    } catch (exception) {
      if (generation != _previewGeneration) return;
      if (exception is ImagePreviewCancelledException) {
        measuring = false;
        applyingParameters = false;
        notifyListeners();
        return;
      }
      measuring = false;
      resultCurrent = false;
      _optimizationFailed = true;
      applyingParameters = false;
      error = exception is FormatException ? exception.message : '$exception';
      notifyListeners();
    }
  }

  void _setSizeEstimate(ImageSizeEstimate value) {
    sizeEstimateListenable.value = value;
  }

  (int, int) _initialSize(ImageInspection value) {
    final cropAspectRatio = _constraints.cropAspectRatio;
    final maxWidth = _constraints.maxWidth;
    final maxHeight = _constraints.maxHeight;
    if (cropAspectRatio != null && maxWidth != null && maxHeight != null) {
      return (maxWidth, maxHeight);
    }
    return _constrainedSize(value.width, value.height);
  }

  double get effectiveAspectRatio {
    final value = inspection;
    if (value == null) return 1;
    if (resizeMode == ImageResizeMode.crop && cropRegion.hasFreeformBounds) {
      final selectedWidth = value.width * (cropRegion.right! - cropRegion.left!);
      final selectedHeight = value.height * (cropRegion.bottom! - cropRegion.top!);
      if (selectedWidth > 0 && selectedHeight > 0) {
        return selectedWidth / selectedHeight;
      }
    }
    return _constraints.cropAspectRatio ?? value.width / value.height;
  }

  void _updateFreeformCropSize(ImageInspection value) {
    final size = _automaticSize(value);
    width = size.$1;
    height = size.$2;
  }

  (int, int) _automaticSize(ImageInspection value) {
    if (resizeMode != ImageResizeMode.crop ||
        _constraints.cropAspectRatio != null) {
      return _initialSize(value);
    }
    final region = cropRegion;
    final selectedWidth = region.hasFreeformBounds
        ? math.max(1, (value.width * (region.right! - region.left!)).round())
        : value.width;
    final selectedHeight = region.hasFreeformBounds
        ? math.max(1, (value.height * (region.bottom! - region.top!)).round())
        : value.height;
    return _constrainedSize(selectedWidth, selectedHeight);
  }

  (int, int) _constrainedSize(int sourceWidth, int sourceHeight) {
    var scale = 1.0;
    if (_constraints.maxWidth != null && sourceWidth > _constraints.maxWidth!) {
      scale = math.min(scale, _constraints.maxWidth! / sourceWidth);
    }
    if (_constraints.maxHeight != null && sourceHeight > _constraints.maxHeight!) {
      scale = math.min(scale, _constraints.maxHeight! / sourceHeight);
    }
    if (_constraints.maxMegapixels != null &&
        sourceWidth * sourceHeight > _constraints.maxMegapixels! * 1000000) {
      scale = math.min(
        scale,
        math.sqrt(
          (_constraints.maxMegapixels! * 1000000) /
              (sourceWidth * sourceHeight),
        ),
      );
    }
    return (
      math.max(1, (sourceWidth * scale).floor()),
      math.max(1, (sourceHeight * scale).floor()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _previewTimer?.cancel();
    _previewGeneration++;
    _repository.cancelPreview();
    sizeEstimateListenable.dispose();
    super.dispose();
  }
}
