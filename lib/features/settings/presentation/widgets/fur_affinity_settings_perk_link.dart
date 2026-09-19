import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'fur_affinity_settings_styles.dart';

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
