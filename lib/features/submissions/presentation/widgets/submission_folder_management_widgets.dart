import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_styles.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

class FaPlusPerkLink extends StatefulWidget {
  const FaPlusPerkLink({
    super.key,
    required this.text,
    required this.iconUri,
    required this.onTap,
  });

  final String text;
  final Uri? iconUri;
  final VoidCallback? onTap;

  @override
  State<FaPlusPerkLink> createState() => _FaPlusPerkLinkState();
}

class _FaPlusPerkLinkState extends State<FaPlusPerkLink> {
  late final TapGestureRecognizer _linkRecognizer;

  static const TextStyle _linkStyle = TextStyle(
    color: managementAccent,
    fontWeight: FontWeight.w700,
  );

  @override
  void initState() {
    super.initState();
    _linkRecognizer = TapGestureRecognizer()..onTap = widget.onTap;
  }

  @override
  void didUpdateWidget(FaPlusPerkLink oldWidget) {
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
      button: widget.onTap != null,
      link: widget.onTap != null,
      label: 'FA+ Member Perk: ${widget.text}',
      child: Text.rich(
        TextSpan(
          style: const TextStyle(color: Colors.white70, height: 1.3),
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
            TextSpan(text: widget.text),
          ],
        ),
      ),
    );
  }
}

class ManagementCard extends StatelessWidget {
  const ManagementCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: managementCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class CardHeading extends StatelessWidget {
  const CardHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SubmissionManagementShrinkableText(
      text,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: SubmissionManagementShrinkableText(
        text,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ManagementCard(
      child: SubmissionManagementShrinkableText(
        text,
        style: const TextStyle(color: Colors.white60),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: managementAccent,
                foregroundColor: Colors.black,
              ),
              child: const SubmissionManagementShrinkableText('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
