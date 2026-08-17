import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/shared/utils/utils.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

const Color furAffinitySettingsAccent = Color(0xFFE09321);
const Color furAffinitySettingsBackground = Colors.black;
const Color furAffinitySettingsGroup = Color(0xFF1C1C1E);
const Color furAffinitySettingsField = Color(0xFF2C2C2E);
const Color furAffinitySettingsDivider = Color(0xFF38383A);
const Color furAffinitySettingsSecondary = Color(0xFF98989D);

class IosSettingsSection extends StatelessWidget {
  const IosSettingsSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
              child: Text(
                header!.toUpperCase(),
                style: const TextStyle(
                  color: furAffinitySettingsSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: furAffinitySettingsGroup,
              child: Column(children: _withDividers()),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
              child: Text(
                footer!,
                style: const TextStyle(
                  color: furAffinitySettingsSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _withDividers() {
    final widgets = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        widgets.add(
          const Divider(
            height: 1,
            thickness: 0.5,
            indent: 16,
            endIndent: 16,
            color: furAffinitySettingsDivider,
          ),
        );
      }
      widgets.add(children[index]);
    }
    return widgets;
  }
}

class IosSettingsRow extends StatelessWidget {
  const IosSettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.verticalPadding = 12,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? Colors.white : Colors.white38;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: verticalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (leading != null) ...[
                    SizedBox(width: 30, child: Center(child: leading)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(color: foreground, fontSize: 16),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              if (subtitle != null || subtitleWidget != null) ...[
                const SizedBox(height: 5),
                subtitleWidget ??
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: enabled
                            ? furAffinitySettingsSecondary
                            : Colors.white30,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class IosSettingsNavigationRow extends StatelessWidget {
  const IosSettingsNavigationRow({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IosSettingsRow(
      title: title,
      leading: Icon(icon, color: furAffinitySettingsAccent, size: 22),
      trailing: const Icon(
        Icons.chevron_right,
        color: furAffinitySettingsSecondary,
      ),
      onTap: onTap,
    );
  }
}

class IosSettingsLinkRow extends StatelessWidget {
  const IosSettingsLinkRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: furAffinitySettingsAccent,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.open_in_new_rounded,
                    color: furAffinitySettingsAccent,
                    size: 17,
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: furAffinitySettingsSecondary,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class IosSettingsSwitchRow extends StatelessWidget {
  const IosSettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IosSettingsRow(
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      verticalPadding: compact ? 4 : 12,
      onTap: enabled ? () => onChanged(!value) : null,
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: furAffinitySettingsAccent,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class IosSettingsValueRow extends StatelessWidget {
  const IosSettingsValueRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    required this.value,
    required this.onTap,
    this.enabled = true,
    this.stacked = false,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final String value;
  final VoidCallback onTap;
  final bool enabled;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? Colors.white : Colors.white38;
    final secondary =
    enabled ? furAffinitySettingsSecondary : Colors.white30;

    if (!stacked) {
      return IosSettingsRow(
        title: title,
        subtitle: subtitle,
        subtitleWidget: subtitleWidget,
        enabled: enabled,
        onTap: onTap,
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 165),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: enabled
                    ? furAffinitySettingsSecondary
                    : Colors.white24,
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Title
              Text(
                title,
                maxLines: 1,
                style: TextStyle(
                  color: foreground,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 5),

              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: TextStyle(
                          color: secondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: enabled
                        ? furAffinitySettingsSecondary
                        : Colors.white24,
                  ),
                ],
              ),

              if (subtitle != null || subtitleWidget != null) ...[
                const SizedBox(height: 5),
                subtitleWidget ??
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: secondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class IosSettingsPerkLink extends StatefulWidget {
  const IosSettingsPerkLink({
    super.key,
    required this.message,
    required this.iconUri,
    required this.onTap,
  });

  final String message;
  final Uri? iconUri;
  final VoidCallback onTap;

  @override
  State<IosSettingsPerkLink> createState() => _IosSettingsPerkLinkState();
}

class _IosSettingsPerkLinkState extends State<IosSettingsPerkLink> {
  late final TapGestureRecognizer _linkRecognizer;

  static const TextStyle _linkStyle = TextStyle(
    color: furAffinitySettingsAccent,
    fontWeight: FontWeight.w700,
  );

  @override
  void initState() {
    super.initState();
    _linkRecognizer = TapGestureRecognizer()..onTap = widget.onTap;
  }

  @override
  void didUpdateWidget(IosSettingsPerkLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    _linkRecognizer.onTap = widget.onTap;
  }

  @override
  void dispose() {
    _linkRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      link: true,
      label: 'FA+ Member Perk: ${widget.message}',
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            color: furAffinitySettingsSecondary,
            fontSize: 12,
            height: 1.3,
          ),
          children: [
            TextSpan(
              text: 'FA+',
              style: _linkStyle,
              recognizer: _linkRecognizer,
            ),
            if (widget.iconUri != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.translucent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FaNetworkImage(
                      widget.iconUri.toString(),
                      width: 14,
                      height: 14,
                      filterQuality: FilterQuality.none,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(width: 14, height: 14),
                    ),
                  ),
                ),
              ),
            if (widget.iconUri == null) const TextSpan(text: ' '),
            TextSpan(
              text: 'Member Perk: ',
              style: _linkStyle,
              recognizer: _linkRecognizer,
            ),
            TextSpan(text: widget.message),
          ],
        ),
      ),
    );
  }
}

class IosSettingsTextFieldRow extends StatelessWidget {
  const IosSettingsTextFieldRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.controller,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.maxLength,
    this.autofillHints,
  });

  final String title;
  final String? subtitle;
  final TextEditingController controller;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLength;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white38,
              fontSize: 16,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(
                color: enabled
                    ? furAffinitySettingsSecondary
                    : Colors.white30,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 9),
          TextField(
            controller: controller,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            maxLength: maxLength,
            autofillHints: autofillHints,
            cursorColor: furAffinitySettingsAccent,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white38,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              filled: true,
              fillColor: furAffinitySettingsField,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(
                  color: furAffinitySettingsAccent,
                ),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IosSettingsActionButton extends StatelessWidget {
  const IosSettingsActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: furAffinitySettingsAccent,
            foregroundColor: Colors.black,
            disabledBackgroundColor: furAffinitySettingsAccent.withValues(
              alpha: 0.45,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class SettingsSaveAction extends StatelessWidget {
  const SettingsSaveAction({
    super.key,
    required this.dirty,
    required this.saving,
    required this.onPressed,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: furAffinitySettingsAccent,
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'Save changes',
      onPressed: dirty ? onPressed : null,
      icon: Icon(
        Icons.check,
        color: dirty ? furAffinitySettingsAccent : Colors.grey,
      ),
    );
  }
}

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

void showSettingsMutationSnackBar(
  BuildContext context, {
  required String section,
  required FaSettingsMutationResult result,
  String? successText,
  String? failureText,
}) {
  if (result.success) {
    showAppSnackBar(
      context,
      successText ?? '$section settings changed successfully.',
      backgroundColor: Colors.green.shade700,
    );
    return;
  }

  final code = result.statusCode == null
      ? 'network error'
      : 'HTTP ${result.statusCode}';
  final detail = _safeResultDetail(result.message);
  final suffix = detail == null ? code : '$code: $detail';
  showAppSnackBar(
    context,
    failureText == null
        ? '$section settings change failed ($suffix).'
        : '$failureText ($suffix).',
    backgroundColor: Colors.red.shade700,
    durationSeconds: 4,
  );
}

String settingsLoadFailureText(Object error) {
  if (error is FaSettingsRequestException && error.statusCode != null) {
    return 'Failed to load settings (HTTP ${error.statusCode}).';
  }
  return 'Failed to load settings.';
}

String? _safeResultDetail(String? message) {
  final cleaned = message?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  if (cleaned.isEmpty) return null;
  if (cleaned.length <= 100) return cleaned;
  return '${cleaned.substring(0, 97).trim()}...';
}
