import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/image_tools/domain/image_optimizer_models.dart';
import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_styles.dart';

class ImageMetricsRow extends StatelessWidget {
  const ImageMetricsRow({
    super.key,
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

  Color _valueColor(bool fits) => fits ? success : danger;

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
            color: orange,
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
                          color: success,
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
                    const TextSpan(text: '×', style: TextStyle(color: muted)),
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
                          color: success,
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
                          color: success,
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
        color: surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: orange, size: 17),
            const SizedBox(width: 6),
            child,
          ],
        ),
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
