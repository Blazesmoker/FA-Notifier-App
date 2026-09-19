import 'package:material_ui/material_ui.dart';

class FolderNameChip extends StatelessWidget {
  const FolderNameChip({
    super.key,
    required this.name,
    required this.color,
    this.onTap,
  });

  final String name;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor =
        color.computeLuminance() > 0.42 ? Colors.black : Colors.white;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              name,
              softWrap: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
