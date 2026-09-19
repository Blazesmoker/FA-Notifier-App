import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/image_tools/presentation/widgets/image_optimizer_styles.dart';

class FullWidthRoundedSliderTrackShape
    extends RoundedRectSliderTrackShape {
  const FullWidthRoundedSliderTrackShape();

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

class ModeButton extends StatelessWidget {
  const ModeButton({
    super.key,
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
      color: selected ? orange : surfaceRaised,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: selected
            ? Colors.black.withValues(alpha: 0.12)
            : orange.withValues(alpha: 0.18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? orange : const Color(0xFF4A4A4A)),
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
              Icon(icon, size: 19, color: selected ? Colors.black : orange),
            ],
          ),
        ),
      ),
    );
  }
}
