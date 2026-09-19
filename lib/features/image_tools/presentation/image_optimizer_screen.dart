import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';
import 'package:fanotifier/features/image_tools/domain/image_optimizer_repository.dart';
import 'package:fanotifier/features/image_tools/presentation/image_optimizer_controller.dart';
import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_comparison_card.dart';
import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_metrics_row.dart';
import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_settings.dart';
import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_styles.dart';
import 'package:fanotifier/features/profile/domain/avatar_image_data.dart';
import 'package:fanotifier/features/profile/presentation/image_inspect_screen.dart';
import 'package:fanotifier/shared/widgets/dashed_loading_indicator.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

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
            backgroundColor: surfaceRaised,
            title: const Text('Some quality may be lost'),
            content: Text(
              animated
                  ? 'The file cannot meet the selected limits without changing its size or color palette. All animation frames, timing, and looping will be preserved. The original file will stay untouched.'
                  : 'The file cannot meet the selected limits without resizing or re-encoding it. The original file will stay untouched and the app will create a separate changed copy.',
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: muted),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: orange,
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
                              child: Center(child: CircularProgressIndicator(color: orange)),
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
      child: ImageComparisonCard(
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
              : (inspection.format ?? ImageOutputFormat.png).extension,
        ),
        changed: AvatarImageData(
          bytes: changed?.bytes ?? _controller.displaySourceBytes,
          extension: changed?.format.extension ??
              (inspection.format ?? ImageOutputFormat.png).extension,
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
        color: surface,
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: true,
          iconColor: orange,
          collapsedIconColor: orange,
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
                    color: orange,
                  ),
                ),
            ],
          ),
          subtitle: Text(
            'Frame ${frame + 1} of ${inspection.frameCount}',
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: orange,
                inactiveTrackColor: const Color(0xFF4A4A4A),
                thumbColor: orange,
                overlayColor: orange.withValues(alpha: 0.16),
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
                    backgroundColor: orange,
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
                    backgroundColor: orange,
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
    final statusColor = fits ? success : danger;
    final outputWidth = result?.width ?? _controller.width;
    final outputHeight = result?.height ?? _controller.height;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: orange),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ImageMetricsRow(
            label: 'Original',
            byteLength: inspection.byteLength,
            width: inspection.width,
            height: inspection.height,
            constraints: widget.constraints,
          ),
          const SizedBox(height: 10),
          ImageMetricsRow(
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
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickSettings() {
    return buildImageOptimizerQuickSettings(
      controller: _controller,
      constraints: widget.constraints,
      onManualSettingChanged: _manualSettingChanged,
      onCropChanged: (value) {
        _lossyApproved = false;
        _controller.setCropRegion(value);
      },
      onCropInteractionChanged: _setCropInteracting,
    );
  }

  Widget _buildAdvancedSettings() {
    return buildImageOptimizerAdvancedSettings(
      context: context,
      controller: _controller,
      constraints: widget.constraints,
      widthController: _widthController,
      heightController: _heightController,
      onReset: () {
        _lossyApproved = false;
        HapticFeedback.selectionClick();
        _controller.resetAdvancedSettings();
      },
      onDimensionChanged: (widthChanged) =>
          _dimensionChanged(widthChanged: widthChanged),
      onFinishDimensionEditing: _finishDimensionEditing,
      onManualSettingChanged: _manualSettingChanged,
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
                backgroundColor: orange,
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
    final color = error ? danger : orange;
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
