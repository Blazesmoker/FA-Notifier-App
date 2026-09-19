import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'fur_affinity_settings_styles.dart';

class _SettingsSheetTopBorder extends ShapeBorder {
  const _SettingsSheetTopBorder({
    this.radius = 28,
    this.side = const BorderSide(
      color: furAffinitySettingsDivider,
      width: 0.5,
    ),
  });

  final double radius;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final effectiveRadius = math.min(
      radius,
      math.min(rect.width / 2, rect.height / 2),
    );
    return Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(effectiveRadius),
          topRight: Radius.circular(effectiveRadius),
        ),
      );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    final inset = side.width / 2;
    if (rect.width <= side.width || rect.height <= side.width) return;
    final effectiveRadius = math.min(
      radius,
      math.min(rect.width / 2, rect.height / 2),
    );
    final arcRadius = effectiveRadius - inset;
    final path = Path()
      ..moveTo(rect.left + inset, rect.top + effectiveRadius)
      ..arcTo(
        Rect.fromCircle(
          center: Offset(
            rect.left + effectiveRadius,
            rect.top + effectiveRadius,
          ),
          radius: arcRadius,
        ),
        math.pi,
        math.pi / 2,
        false,
      )
      ..lineTo(rect.right - effectiveRadius, rect.top + inset)
      ..arcTo(
        Rect.fromCircle(
          center: Offset(
            rect.right - effectiveRadius,
            rect.top + effectiveRadius,
          ),
          radius: arcRadius,
        ),
        -math.pi / 2,
        math.pi / 2,
        false,
      );
    final paint = Paint()
      ..color = side.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = side.width;
    canvas.drawPath(path, paint);
  }

  @override
  ShapeBorder scale(double t) {
    return _SettingsSheetTopBorder(
      radius: radius * t,
      side: side.scale(t),
    );
  }
}

Future<String?> showSettingsChoice(
  BuildContext context, {
  required String title,
  required String currentValue,
  required List<FaFormOption> options,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: furAffinitySettingsBackground,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints.tightFor(
      width: MediaQuery.sizeOf(context).width,
    ),
    shape: const _SettingsSheetTopBorder(),
    clipBehavior: Clip.antiAlias,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, _) => const Divider(
              height: 1,
              indent: 12,
              endIndent: 12,
              color: furAffinitySettingsDivider,
            ),
            itemBuilder: (context, index) {
              final option = options[index];
              final selected = option.value == currentValue;
              return ListTile(
                title: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(option.label, maxLines: 1),
                ),
                trailing: selected
                    ? const Icon(
                        Icons.check,
                        color: furAffinitySettingsAccent,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(option.value),
              );
            },
          ),
        ),
      ],
    ),
  );
}
