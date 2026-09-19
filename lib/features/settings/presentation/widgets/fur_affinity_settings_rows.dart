import 'package:material_ui/material_ui.dart';
import 'fur_affinity_settings_styles.dart';

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
      trailing: Switch(
        value: value,
        activeThumbColor: furAffinitySettingsAccent,
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
