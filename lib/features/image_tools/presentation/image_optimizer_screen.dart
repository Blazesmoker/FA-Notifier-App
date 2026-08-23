import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';
import 'package:fanotifier/features/image_tools/domain/image_optimizer_repository.dart';
import 'package:fanotifier/features/image_tools/presentation/freeform_image_crop_editor.dart';
import 'package:fanotifier/features/image_tools/presentation/image_crop_editor.dart';
import 'package:fanotifier/features/image_tools/presentation/image_optimizer_controller.dart';
import 'package:fanotifier/features/profile/domain/avatar_image_data.dart';
import 'package:fanotifier/features/profile/presentation/image_inspect_screen.dart';
import 'package:fanotifier/shared/widgets/dashed_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

const _orange = Color(0xFFE09321);
const _surface = Color(0xFF1C1C1C);
const _surfaceRaised = Color(0xFF292929);
const _muted = Color(0xFFB8B8B8);
const _success = Color(0xFF65C466);
const _danger = Color(0xFFFF6B6B);
const _comparisonSliderHorizontalPadding = 20.0;
const _sliderOverlayRadius = 18.7;

class ImageOptimizerScreen extends StatefulWidget {
  const ImageOptimizerScreen({
    super.key,
    required this.originalBytes,
    required this.originalFileName,
    required this.constraints,
  });

  final Uint8List originalBytes;
  final String originalFileName;
  final ImageOptimizationConstraints constraints;

  @override
  State<ImageOptimizerScreen> createState() => _ImageOptimizerScreenState();
}

class _ImageOptimizerScreenState extends State<ImageOptimizerScreen> {
  late final ImageOptimizerController _controller;
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _frameController = TextEditingController(text: '1');
  final _frameFocusNode = FocusNode();
  bool _lossyApproved = false;
  bool _comparisonZoomed = false;
  bool _comparisonInteracting = false;
  bool _cropInteracting = false;
  int? _frameDraft;

  @override
  void initState() {
    super.initState();
    _controller = ImageOptimizerController(
      repository: context.read<ImageOptimizerRepository>(),
      originalBytes: widget.originalBytes,
      originalFileName: widget.originalFileName,
      constraints: widget.constraints,
    );
    _controller.addListener(_syncDimensionFields);
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncDimensionFields)
      ..dispose();
    _widthController.dispose();
    _heightController.dispose();
    _frameController.dispose();
    _frameFocusNode.dispose();
    super.dispose();
  }

  void _syncDimensionFields() {
    if (_controller.inspection == null) return;
    final width = '${_controller.width}';
    final height = '${_controller.height}';
    if (_widthController.text != width) _widthController.text = width;
    if (_heightController.text != height) _heightController.text = height;
    if (!_frameFocusNode.hasFocus && _frameDraft == null) {
      final frame = '${_controller.selectedFrameIndex + 1}';
      if (_frameController.text != frame) _frameController.text = frame;
    }
  }

  void _dimensionChanged({required bool widthChanged}) {
    final inspection = _controller.inspection;
    if (inspection == null) return;
    var width = int.tryParse(_widthController.text);
    var height = int.tryParse(_heightController.text);
    final aspectRatio = _controller.effectiveAspectRatio;
    if (widthChanged && width != null && width > 0) {
      height = (width / aspectRatio).round();
      _heightController.text = '$height';
    } else if (!widthChanged && height != null && height > 0) {
      width = (height * aspectRatio).round();
      _widthController.text = '$width';
    }
    if (width != null && height != null && width > 0 && height > 0) {
      _lossyApproved = false;
      _controller.setDimensions(width, height);
    }
  }

  Future<bool> _confirmLossy({required bool animated}) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _surfaceRaised,
            title: const Text('Some quality may be lost'),
            content: Text(
              animated
                  ? 'The file cannot meet the selected limits without changing its size or color palette. All animation frames, timing, and looping will be preserved. The original file will stay untouched.'
                  : 'The file cannot meet the selected limits without resizing or re-encoding it. The original file will stay untouched and the app will create a separate changed copy.',
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: _muted),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _saveAndUse() async {
    final result = _controller.result;
    final inspection = _controller.inspection;
    if (result == null || inspection == null) return;
    if (!result.lossless && !_lossyApproved) {
      final accepted = await _confirmLossy(
        animated: inspection.animated && !_controller.selectsAnimatedFrame,
      );
      if (!accepted || !mounted) return;
      _lossyApproved = true;
    }
    final saved = await _controller.saveCopy();
    if (!mounted || !saved) return;
    Navigator.of(context).pop(result);
  }

  void _manualSettingChanged(VoidCallback change) {
    _lossyApproved = false;
    HapticFeedback.selectionClick();
    change();
  }

  void _finishDimensionEditing() {
    FocusScope.of(context).unfocus();
    _controller.createPreview();
  }

  void _setComparisonZoomed(bool value) {
    if (_comparisonZoomed == value && (value || !_comparisonInteracting)) return;
    setState(() {
      _comparisonZoomed = value;
      if (!value) _comparisonInteracting = false;
    });
  }

  void _setComparisonInteracting(bool value) {
    final interacting = value && _comparisonZoomed;
    if (_comparisonInteracting == interacting) return;
    setState(() => _comparisonInteracting = interacting);
  }

  void _setCropInteracting(bool value) {
    if (_cropInteracting == value) return;
    setState(() => _cropInteracting = value);
    if (value) {
      _controller.beginCropAdjustment();
    } else {
      _controller.finishCropAdjustment();
    }
  }

  Future<void> _selectFrame(int value) async {
    final inspection = _controller.inspection;
    if (inspection == null) return;
    final frame = value.clamp(0, inspection.frameCount - 1).toInt();
    _frameController.text = '${frame + 1}';
    setState(() => _frameDraft = null);
    _lossyApproved = false;
    HapticFeedback.selectionClick();
    await _controller.setFrameIndex(frame);
  }

  void _commitFrameText() {
    final value = int.tryParse(_frameController.text);
    final inspection = _controller.inspection;
    if (inspection == null) return;
    _selectFrame((value ?? _controller.selectedFrameIndex + 1) - 1);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final inspection = _controller.inspection;
        final showProcessingIndicator = inspection != null &&
            ((_controller.measuring && _controller.result == null) ||
                (_controller.applyingParameters &&
                    (_controller.working ||
                        _controller.measuring ||
                        _controller.frameLoading)));
        return Scaffold(
          backgroundColor: Colors.black,
          extendBody: true,
          appBar: AppBar(
            title: Text(widget.constraints.title),
            actions: [
              if (showProcessingIndicator)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(child: DashedLoadingIndicator()),
                ),
            ],
          ),
          body: _controller.working && inspection == null
              ? const Center(
                  child: PulsatingLoadingIndicator(
                    size: 78,
                    assetPath: 'assets/icons/fathemed.png',
                  ),
                )
              : inspection == null
                  ? _ErrorPanel(message: _controller.error ?? 'Could not read this image.')
                  : Stack(
                      children: [
                        ListView(
                          physics: _comparisonInteracting || _cropInteracting
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 150),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 760),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildComparison(),
                                    if (_controller.selectsAnimatedFrame) ...[
                                      const SizedBox(height: 14),
                                      _buildFrameSelector(),
                                    ],
                                    const SizedBox(height: 14),
                                    _buildQuickSettings(),
                                    const SizedBox(height: 14),
                                    _buildLimitCard(),
                                    if (widget.constraints.siteConvertsToJpeg &&
                                        inspection.animated) ...[
                                      const SizedBox(height: 12),
                                      const _Notice(
                                        icon: Icons.info_outline,
                                        text: 'Fur Affinity displays profile banners as JPG. Choose the GIF frame you want to use as the static banner.',
                                      ),
                                    ],
                                    const SizedBox(height: 14),
                                    _buildAdvancedSettings(),
                                    if (_controller.error != null) ...[
                                      const SizedBox(height: 14),
                                      _Notice(
                                        icon: Icons.error_outline,
                                        text: _controller.error!,
                                        error: true,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_controller.working)
                          const Positioned.fill(
                            child: ColoredBox(
                              color: Color(0x99000000),
                              child: Center(child: CircularProgressIndicator(color: _orange)),
                            ),
                          ),
                      ],
                    ),
          bottomNavigationBar: inspection == null ? null : _buildBottomBar(),
        );
      },
    );
  }

  Widget _buildComparison() {
    final source = _controller.displaySourceBytes;
    final currentResult = _controller.resultCurrent ? _controller.result : null;
    final after = currentResult?.bytes ?? source;
    return RepaintBoundary(
      child: _ImageComparisonCard(
        originalBytes: source,
        changedBytes: after,
        onOpenOriginal: () => _openComparison(0),
        onOpenChanged: () => _openComparison(1),
        onZoomChanged: _setComparisonZoomed,
        onInteractionChanged: _setComparisonInteracting,
      ),
    );
  }

  Future<void> _openComparison(int initialIndex) async {
    final inspection = _controller.inspection;
    if (inspection == null) return;
    final changed = _controller.resultCurrent ? _controller.result : null;
    await Navigator.of(context).push(
      ImageInspectScreen.comparisonRoute(
        original: AvatarImageData(
          bytes: _controller.displaySourceBytes,
          extension: _controller.selectsAnimatedFrame
              ? ImageOutputFormat.png.extension
              : inspection.format.extension,
        ),
        changed: AvatarImageData(
          bytes: changed?.bytes ?? _controller.displaySourceBytes,
          extension: changed?.format.extension ?? inspection.format.extension,
        ),
        initialIndex: initialIndex,
      ),
    );
  }

  Widget _buildFrameSelector() {
    final inspection = _controller.inspection!;
    final frame = (_frameDraft ?? _controller.selectedFrameIndex)
        .clamp(0, inspection.frameCount - 1)
        .toInt();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Card(
        color: _surface,
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: true,
          iconColor: _orange,
          collapsedIconColor: _orange,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  'Choose animation frame',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              if (_controller.frameLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _orange,
                  ),
                ),
            ],
          ),
          subtitle: Text(
            'Frame ${frame + 1} of ${inspection.frameCount}',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _orange,
                inactiveTrackColor: const Color(0xFF4A4A4A),
                thumbColor: _orange,
                overlayColor: _orange.withValues(alpha: 0.16),
              ),
              child: Slider(
                value: frame.toDouble(),
                min: 0,
                max: (inspection.frameCount - 1).toDouble(),
                divisions: inspection.frameCount - 1,
                onChanged: _controller.frameLoading
                    ? null
                    : (value) {
                        final next = value.round();
                        setState(() => _frameDraft = next);
                        _frameController.text = '${next + 1}';
                      },
                onChangeEnd: (value) => _selectFrame(value.round()),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF4D3E20),
                  ),
                  onPressed: frame > 0 && !_controller.frameLoading
                      ? () => _selectFrame(frame - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Previous frame',
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: _frameController,
                    focusNode: _frameFocusNode,
                    enabled: !_controller.frameLoading,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _commitFrameText(),
                    onTapOutside: (_) {
                      _commitFrameText();
                      _frameFocusNode.unfocus();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF4D3E20),
                  ),
                  onPressed: frame < inspection.frameCount - 1 &&
                          !_controller.frameLoading
                      ? () => _selectFrame(frame + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Next frame',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitCard() {
    return ValueListenableBuilder<ImageSizeEstimate?>(
      valueListenable: _controller.sizeEstimateListenable,
      builder: (context, estimate, child) => _buildLimitCardContent(estimate),
    );
  }

  Widget _buildLimitCardContent(ImageSizeEstimate? estimate) {
    final inspection = _controller.inspection!;
    final result = _controller.resultCurrent ? _controller.result : null;
    final outputBytes = estimate?.byteLength ?? inspection.byteLength;
    final fits = _controller.currentEstimateFits;
    final estimated = estimate?.accuracy != ImageSizeAccuracy.measured;
    final statusColor = fits ? _success : _danger;
    final outputWidth = result?.width ?? _controller.width;
    final outputHeight = result?.height ?? _controller.height;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                fits ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fits
                      ? 'Fits the upload limits'
                      : 'Does not fit the upload limits',
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
                ),
              ),
              if (_controller.measuring)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _orange),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _ImageMetricsRow(
            label: 'Original',
            byteLength: inspection.byteLength,
            width: inspection.width,
            height: inspection.height,
            constraints: widget.constraints,
          ),
          const SizedBox(height: 10),
          _ImageMetricsRow(
            label: 'Changed',
            byteLength: outputBytes,
            width: outputWidth,
            height: outputHeight,
            constraints: widget.constraints,
            estimated: estimated,
          ),
          if (_controller.measuring || estimated) ...[
            const SizedBox(height: 8),
            Text(
              _controller.measuring
                  ? 'Checking the exact size…'
                  : 'Approximate size. The exact value appears after processing.',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickSettings() {
    final inspection = _controller.inspection!;
    final selectedMode = _controller.resizeMode;
    return Card(
      color: _surface,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ModeButton(
                    label: 'Fit',
                    icon: Icons.fit_screen_outlined,
                    selected: selectedMode == ImageResizeMode.fit,
                    onTap: () => _manualSettingChanged(
                      () => _controller.setResizeMode(ImageResizeMode.fit),
                    ),
                  ),
                  _ModeButton(
                    label: 'Crop',
                    icon: Icons.crop_rounded,
                    selected: selectedMode == ImageResizeMode.crop,
                    onTap: () => _manualSettingChanged(
                      () => _controller.setResizeMode(ImageResizeMode.crop),
                    ),
                  ),
                  if (widget.constraints.allowStretch)
                    _ModeButton(
                      label: 'Stretch',
                      icon: Icons.aspect_ratio_rounded,
                      selected: selectedMode == ImageResizeMode.stretch,
                      onTap: () => _manualSettingChanged(
                        () => _controller.setResizeMode(ImageResizeMode.stretch),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  switch (selectedMode) {
                    ImageResizeMode.fit => widget.constraints.allowStretch
                        ? 'Shows the whole image. Empty space may appear around it.'
                        : 'Shows the whole image without cutting the edges.',
                    ImageResizeMode.crop =>
                      widget.constraints.cropAspectRatio == null
                          ? 'Choose the exact part of the image you want to keep.'
                          : 'Fills the frame. Some edges may be cut.',
                    ImageResizeMode.stretch =>
                      'Forces the image into the banner shape. It may look distorted.',
                  },
                  key: ValueKey(selectedMode),
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ),
            ),
            if (widget.constraints.cropAspectRatio != null &&
                selectedMode == ImageResizeMode.crop) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ImageCropEditor(
                  bytes: _controller.displaySourceBytes,
                  sourceWidth: inspection.width,
                  sourceHeight: inspection.height,
                  aspectRatio: widget.constraints.cropAspectRatio!,
                  outputWidth: _controller.width,
                  outputHeight: _controller.height,
                  value: _controller.cropRegion,
                  onChanged: (value) {
                    _lossyApproved = false;
                    _controller.setCropRegion(value);
                  },
                  onInteractionChanged: _setCropInteracting,
                ),
              ),
            ],
            if (widget.constraints.cropAspectRatio == null &&
                selectedMode == ImageResizeMode.crop) ...[
              const SizedBox(height: 9),
              FreeformImageCropEditor(
                bytes: _controller.displaySourceBytes,
                sourceWidth: inspection.width,
                sourceHeight: inspection.height,
                value: _controller.cropRegion,
                onChanged: (value) {
                  _lossyApproved = false;
                  _controller.setCropRegion(value);
                },
                onInteractionChanged: _setCropInteracting,
              ),
            ],
            if (_controller.format == ImageOutputFormat.gif &&
                inspection.animated) ...[
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'All animation frames, timing, and looping are preserved.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings() {
    final inspection = _controller.inspection!;
    final formats = widget.constraints.allowedFormats
        .where((format) =>
            !inspection.animated ||
            _controller.selectsAnimatedFrame ||
            format == ImageOutputFormat.gif)
        .toList();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Card(
        color: _surface,
        margin: EdgeInsets.zero,
        child: ExpansionTile(
        initiallyExpanded: false,
        onExpansionChanged: _controller.setAdvancedExpanded,
        iconColor: _orange,
        collapsedIconColor: _orange,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        title: Row(
          children: [
            const Text(
              'Advanced settings',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (_controller.advancedSettingsChanged) ...[
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  _lossyApproved = false;
                  HapticFeedback.selectionClick();
                  _controller.resetAdvancedSettings();
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Reset',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(width: 5),
                    Icon(Icons.restart_alt_rounded, size: 17),
                  ],
                ),
              ),
            ],
          ],
        ),
        subtitle: const Text(
          'Exact size and file format',
          style: TextStyle(color: _muted),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _widthController,
                  cursorColor: _orange,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: _inputDecoration('Width'),
                  onChanged: (_) => _dimensionChanged(widthChanged: true),
                  onEditingComplete: _finishDimensionEditing,
                  onTapOutside: (_) => _finishDimensionEditing(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 9),
                child: Text('×', style: TextStyle(color: _muted)),
              ),
              Expanded(
                child: TextField(
                  controller: _heightController,
                  cursorColor: _orange,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: _inputDecoration('Height'),
                  onChanged: (_) => _dimensionChanged(widthChanged: false),
                  onEditingComplete: _finishDimensionEditing,
                  onTapOutside: (_) => _finishDimensionEditing(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ImageOutputFormat>(
            key: ValueKey(_controller.format),
            initialValue: _controller.format,
            dropdownColor: _surfaceRaised,
            decoration: _inputDecoration('File format'),
            items: [
              for (final format in formats)
                DropdownMenuItem(value: format, child: Text(format.label)),
            ],
            onChanged: (value) {
              if (value == null) return;
              _manualSettingChanged(() => _controller.setFormat(value));
            },
          ),
        ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      filled: true,
      fillColor: _surfaceRaised,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4B4B4B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _orange, width: 1.5),
      ),
    );
  }

  Widget _buildBottomBar() {
    return ValueListenableBuilder<ImageSizeEstimate?>(
      valueListenable: _controller.sizeEstimateListenable,
      builder: (context, estimate, child) => Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            top: -58,
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x1A000000),
                      Color(0x66000000),
                      Color(0xD9000000),
                      Colors.black,
                    ],
                    stops: [0.0, 0.2, 0.48, 0.76, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.black,
                disabledBackgroundColor: const Color(0xFF4D3E20),
                disabledForegroundColor: const Color(0xFF928362),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              onPressed: _controller.canSave &&
                      !_controller.working &&
                      !_controller.measuring
                  ? _saveAndUse
                  : null,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Save & Use',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.check_rounded),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageComparisonCard extends StatefulWidget {
  const _ImageComparisonCard({
    required this.originalBytes,
    required this.changedBytes,
    required this.onOpenOriginal,
    required this.onOpenChanged,
    required this.onZoomChanged,
    required this.onInteractionChanged,
  });

  final Uint8List originalBytes;
  final Uint8List changedBytes;
  final VoidCallback onOpenOriginal;
  final VoidCallback onOpenChanged;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<bool> onInteractionChanged;

  @override
  State<_ImageComparisonCard> createState() => _ImageComparisonCardState();
}

class _ImageComparisonCardState extends State<_ImageComparisonCard> {
  final ValueNotifier<double> _comparisonListenable = ValueNotifier(0.5);
  final TransformationController _previewTransformationController =
      TransformationController();
  Offset _previewDoubleTapPosition = Offset.zero;
  bool _zoomed = false;
  int _activePreviewPointers = 0;

  @override
  void initState() {
    super.initState();
    _previewTransformationController.addListener(
      _handlePreviewTransformationChanged,
    );
  }

  @override
  void dispose() {
    _comparisonListenable.dispose();
    _previewTransformationController.removeListener(
      _handlePreviewTransformationChanged,
    );
    _previewTransformationController.dispose();
    super.dispose();
  }

  void _handlePreviewTransformationChanged() {
    final zoomed =
        _previewTransformationController.value.getMaxScaleOnAxis() > 1.05;
    if (_zoomed == zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
    if (zoomed && _activePreviewPointers > 0) {
      widget.onInteractionChanged(true);
    } else if (!zoomed) {
      widget.onInteractionChanged(false);
    }
  }

  void _handlePreviewPointerDown(PointerDownEvent event) {
    _activePreviewPointers++;
    if (_zoomed) widget.onInteractionChanged(true);
  }

  void _handlePreviewPointerEnd(PointerEvent event) {
    if (_activePreviewPointers > 0) _activePreviewPointers--;
    if (_activePreviewPointers == 0) widget.onInteractionChanged(false);
  }

  void _togglePreviewZoom() {
    final currentScale =
        _previewTransformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _previewTransformationController.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    _previewTransformationController.value = Matrix4.identity()
      ..translateByDouble(
        -_previewDoubleTapPosition.dx * (scale - 1),
        -_previewDoubleTapPosition.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF4A4A4A)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Listener(
            onPointerDown: _handlePreviewPointerDown,
            onPointerUp: _handlePreviewPointerEnd,
            onPointerCancel: _handlePreviewPointerEnd,
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cacheWidth = (constraints.maxWidth *
                        MediaQuery.of(context).devicePixelRatio)
                    .ceil()
                    .clamp(1, 1600)
                    .toInt();
                final changedImage = ColoredBox(
                  color: Colors.black,
                  child: Image.memory(
                    widget.changedBytes,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    cacheWidth: cacheWidth,
                  ),
                );
                final originalImage = ColoredBox(
                  color: Colors.black,
                  child: Image.memory(
                    widget.originalBytes,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    cacheWidth: cacheWidth,
                  ),
                );
                final originalLayer = IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _previewTransformationController,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: originalImage,
                    ),
                    builder: (context, child) => Transform(
                      transform: _previewTransformationController.value,
                      child: child,
                    ),
                  ),
                );
                  return Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onDoubleTapDown: (details) {
                        _previewDoubleTapPosition = details.localPosition;
                      },
                      onDoubleTap: _togglePreviewZoom,
                      child: InteractiveViewer(
                        transformationController:
                            _previewTransformationController,
                        minScale: 1,
                        maxScale: 4,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: changedImage,
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _comparisonListenable,
                        builder: (context, comparison, child) {
                          final dividerLeft =
                              (constraints.maxWidth * comparison - 0.75)
                                  .clamp(0.0, constraints.maxWidth - 1.5)
                                  .toDouble();
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRect(
                                clipper: _FractionClipper(comparison),
                                child: originalLayer,
                              ),
                              Positioned(
                                left: dividerLeft,
                                top: 0,
                                bottom: 0,
                                child: const SizedBox(
                                  width: 1.5,
                                  child: ColoredBox(color: _orange),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
            child: Row(
              children: [
                _PreviewLabel(
                  text: 'Original',
                  onTap: widget.onOpenOriginal,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _comparisonSliderHorizontalPadding,
                    ),
                    child: ValueListenableBuilder<double>(
                      valueListenable: _comparisonListenable,
                      builder: (context, comparison, child) {
                        return SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: _orange,
                            inactiveTrackColor: const Color(0xFF505050),
                            thumbColor: _orange,
                            overlayColor: _orange.withValues(alpha: 0.16),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: _sliderOverlayRadius,
                            ),
                            trackShape:
                                const _FullWidthRoundedSliderTrackShape(),
                          ),
                          child: Semantics(
                            label:
                                'Drag to compare the original and changed image',
                            child: Slider(
                              value: comparison,
                              onChanged: (value) {
                                _comparisonListenable.value = value;
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                _PreviewLabel(
                  text: 'Changed',
                  onTap: widget.onOpenChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullWidthRoundedSliderTrackShape
    extends RoundedRectSliderTrackShape {
  const _FullWidthRoundedSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 0;
    return Rect.fromLTWH(
      offset.dx,
      offset.dy + (parentBox.size.height - trackHeight) / 2,
      parentBox.size.width,
      trackHeight,
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _orange : _surfaceRaised,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: selected
            ? Colors.black.withValues(alpha: 0.12)
            : _orange.withValues(alpha: 0.18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? _orange : const Color(0xFF4A4A4A)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 7),
              Icon(icon, size: 19, color: selected ? Colors.black : _orange),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageMetricsRow extends StatelessWidget {
  const _ImageMetricsRow({
    required this.label,
    required this.byteLength,
    required this.width,
    required this.height,
    required this.constraints,
    this.estimated = false,
  });

  final String label;
  final int byteLength;
  final int width;
  final int height;
  final ImageOptimizationConstraints constraints;
  final bool estimated;

  Color _valueColor(bool fits) => fits ? _success : _danger;

  @override
  Widget build(BuildContext context) {
    final bytesFit = constraints.maxBytes == null ||
        byteLength <= constraints.maxBytes!;
    final widthFit = constraints.maxWidth == null || width <= constraints.maxWidth!;
    final heightFit = constraints.maxHeight == null || height <= constraints.maxHeight!;
    final megapixels = width * height / 1000000;
    final megapixelsFit = constraints.maxMegapixels == null ||
        megapixels <= constraints.maxMegapixels!;
    final widthValueFits = widthFit && megapixelsFit;
    final heightValueFits = heightFit && megapixelsFit;
    final portrait = height > width;
    final equivalentWidth = portrait
        ? constraints.maxMegapixelEquivalentHeight
        : constraints.maxMegapixelEquivalentWidth;
    final equivalentHeight = portrait
        ? constraints.maxMegapixelEquivalentWidth
        : constraints.maxMegapixelEquivalentHeight;
    final pixelLimitWidth = constraints.maxWidth ?? equivalentWidth;
    final pixelLimitHeight = constraints.maxHeight ?? equivalentHeight;
    final usesMegapixelEquivalent = constraints.maxWidth == null &&
        constraints.maxHeight == null &&
        equivalentWidth != null &&
        equivalentHeight != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _orange,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _MetricChip(
              icon: Icons.data_usage_rounded,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${estimated ? '≈ ' : ''}${_formatBytes(byteLength)}',
                      style: TextStyle(
                        color: _valueColor(bytesFit),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (constraints.maxBytes != null)
                      TextSpan(
                        text: ' / ${_formatBytes(constraints.maxBytes!)}',
                        style: const TextStyle(
                          color: _success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _MetricChip(
              icon: Icons.photo_size_select_large_outlined,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$width',
                      style: TextStyle(
                        color: _valueColor(widthValueFits),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: '×', style: TextStyle(color: _muted)),
                    TextSpan(
                      text: '$height px',
                      style: TextStyle(
                        color: _valueColor(heightValueFits),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (pixelLimitWidth != null || pixelLimitHeight != null)
                      TextSpan(
                        text: ' / ${pixelLimitWidth?.toString() ?? 'any'}×${pixelLimitHeight?.toString() ?? 'any'} px${usesMegapixelEquivalent ? ' (2K)' : ''}',
                        style: const TextStyle(
                          color: _success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (constraints.maxMegapixels != null)
              _MetricChip(
                icon: Icons.grid_on_rounded,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${megapixels.toStringAsFixed(2)} MP',
                        style: TextStyle(
                          color: _valueColor(megapixelsFit),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: ' / ${constraints.maxMegapixels} MP',
                        style: const TextStyle(
                          color: _success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _orange, size: 17),
            const SizedBox(width: 6),
            child,
          ],
        ),
      ),
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _orange,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  const _FractionClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FractionClipper oldClipper) => oldClipper.fraction != fraction;
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    this.error = false,
  });

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? _danger : _orange;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 9),
            Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
