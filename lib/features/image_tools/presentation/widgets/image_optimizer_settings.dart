import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';
import 'package:fanotifier/features/image_tools/presentation/freeform_image_crop_editor.dart';
import 'package:fanotifier/features/image_tools/presentation/image_crop_editor.dart';
import 'package:fanotifier/features/image_tools/presentation/image_optimizer_controller.dart';
import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_controls.dart';
import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_styles.dart';

Widget buildImageOptimizerQuickSettings({
  required ImageOptimizerController controller,
  required ImageOptimizationConstraints constraints,
  required void Function(VoidCallback) onManualSettingChanged,
  required ValueChanged<ImageCropRegion> onCropChanged,
  required ValueChanged<bool> onCropInteractionChanged,
}) {
  final inspection = controller.inspection!;
  final selectedMode = controller.resizeMode;
  return Card(
    color: surface,
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
                ModeButton(
                  label: 'Fit',
                  icon: Icons.fit_screen_outlined,
                  selected: selectedMode == ImageResizeMode.fit,
                  onTap: () => onManualSettingChanged(
                    () => controller.setResizeMode(ImageResizeMode.fit),
                  ),
                ),
                ModeButton(
                  label: 'Crop',
                  icon: Icons.crop_rounded,
                  selected: selectedMode == ImageResizeMode.crop,
                  onTap: () => onManualSettingChanged(
                    () => controller.setResizeMode(ImageResizeMode.crop),
                  ),
                ),
                if (constraints.allowStretch)
                  ModeButton(
                    label: 'Stretch',
                    icon: Icons.aspect_ratio_rounded,
                    selected: selectedMode == ImageResizeMode.stretch,
                    onTap: () => onManualSettingChanged(
                      () => controller.setResizeMode(ImageResizeMode.stretch),
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
                  ImageResizeMode.fit => constraints.allowStretch
                      ? 'Shows the whole image. Empty space may appear around it.'
                      : 'Shows the whole image without cutting the edges.',
                  ImageResizeMode.crop =>
                    constraints.cropAspectRatio == null
                        ? 'Choose the exact part of the image you want to keep.'
                        : 'Fills the frame. Some edges may be cut.',
                  ImageResizeMode.stretch =>
                    'Forces the image into the banner shape. It may look distorted.',
                },
                key: ValueKey(selectedMode),
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ),
          ),
          if (constraints.cropAspectRatio != null &&
              selectedMode == ImageResizeMode.crop) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ImageCropEditor(
                bytes: controller.displaySourceBytes,
                sourceWidth: inspection.width,
                sourceHeight: inspection.height,
                aspectRatio: constraints.cropAspectRatio!,
                outputWidth: controller.width,
                outputHeight: controller.height,
                value: controller.cropRegion,
                onChanged: onCropChanged,
                onInteractionChanged: onCropInteractionChanged,
              ),
            ),
          ],
          if (constraints.cropAspectRatio == null &&
              selectedMode == ImageResizeMode.crop) ...[
            const SizedBox(height: 9),
            FreeformImageCropEditor(
              bytes: controller.displaySourceBytes,
              sourceWidth: inspection.width,
              sourceHeight: inspection.height,
              value: controller.cropRegion,
              onChanged: onCropChanged,
              onInteractionChanged: onCropInteractionChanged,
            ),
          ],
          if (controller.format == ImageOutputFormat.gif &&
              inspection.animated) ...[
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'All animation frames, timing, and looping are preserved.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget buildImageOptimizerAdvancedSettings({
  required BuildContext context,
  required ImageOptimizerController controller,
  required ImageOptimizationConstraints constraints,
  required TextEditingController widthController,
  required TextEditingController heightController,
  required VoidCallback onReset,
  required ValueChanged<bool> onDimensionChanged,
  required VoidCallback onFinishDimensionEditing,
  required void Function(VoidCallback) onManualSettingChanged,
}) {
  final inspection = controller.inspection!;
  final formats = constraints.allowedFormats
      .where((format) =>
          !inspection.animated ||
          controller.selectsAnimatedFrame ||
          format == ImageOutputFormat.gif)
      .toList();
  return Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: Card(
      color: surface,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
      initiallyExpanded: false,
      onExpansionChanged: controller.setAdvancedExpanded,
      iconColor: orange,
      collapsedIconColor: orange,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      title: Row(
        children: [
          const Text(
            'Advanced settings',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          if (controller.advancedSettingsChanged) ...[
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.black,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 2,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onReset,
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
        style: TextStyle(color: muted),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: widthController,
                cursorColor: orange,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: _inputDecoration('Width'),
                onChanged: (_) => onDimensionChanged(true),
                onEditingComplete: onFinishDimensionEditing,
                onTapOutside: (_) => onFinishDimensionEditing(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 9),
              child: Text('×', style: TextStyle(color: muted)),
            ),
            Expanded(
              child: TextField(
                controller: heightController,
                cursorColor: orange,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: _inputDecoration('Height'),
                onChanged: (_) => onDimensionChanged(false),
                onEditingComplete: onFinishDimensionEditing,
                onTapOutside: (_) => onFinishDimensionEditing(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ImageOutputFormat>(
          key: ValueKey(controller.format),
          initialValue: controller.format,
          dropdownColor: surfaceRaised,
          decoration: _inputDecoration('File format'),
          items: [
            for (final format in formats)
              DropdownMenuItem(value: format, child: Text(format.label)),
          ],
          onChanged: (value) {
            if (value == null) return;
            onManualSettingChanged(() => controller.setFormat(value));
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
    labelStyle: const TextStyle(color: muted),
    filled: true,
    fillColor: surfaceRaised,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF4B4B4B)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: orange, width: 1.5),
    ),
  );
}

