import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:FANotifier/shared/theme/app_theme.dart';
import 'package:FANotifier/core/preferences/thumbnail_display_settings_provider.dart';
import 'package:FANotifier/shared/navigation/fa_link_handler.dart';
import 'package:provider/provider.dart';

/// Applies an optional rating outline around the thumbnail.
///
/// Reads the toggle from [ThumbnailDisplaySettingsProvider] so changes apply live.
class FaThumbnailOutline extends StatelessWidget {
  final Widget child;
  final String? rating; // "general" | "mature" | "adult" | null
  final double borderRadius;

  const FaThumbnailOutline({
    super.key,
    required this.child,
    required this.rating,
    this.borderRadius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    final showOutline = context.select<ThumbnailDisplaySettingsProvider, bool>(
      (p) => p.showRatingOutline,
    );

    final outlineColor = AppTheme.thumbnailRatingOutlineColor(rating);

    return Stack(
      children: [
        child,
        if (showOutline && outlineColor != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: outlineColor,
                    width: AppTheme.thumbnailRatingOutlineWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Renders the optional title/author caption under a thumbnail.
///
/// Reads the toggle from [ThumbnailDisplaySettingsProvider] so changes apply live.
class FaThumbnailCaption extends StatelessWidget {
  final double maxWidth;
  final String? title;
  final String? author;
  final String? authorProfileUrl;
  final Future<void> Function(String author)? onAuthorTap;

  const FaThumbnailCaption({
    super.key,
    required this.maxWidth,
    required this.title,
    required this.author,
    this.authorProfileUrl,
    this.onAuthorTap,
  });

  @override
  Widget build(BuildContext context) {
    final showText = context.select<ThumbnailDisplaySettingsProvider, bool>(
      (p) => p.showTitleAuthor,
    );
    if (!showText) return const SizedBox.shrink();

    final t = (title ?? '').trim();
    final a = (author ?? '').trim();
    if (t.isEmpty && a.isEmpty) return const SizedBox.shrink();

    final bool hasAuthor = a.isNotEmpty;
    final int titleMaxLines = hasAuthor ? 2 : 3; // total max lines = 3

    final titleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white70,
          fontSize: 12,
        );
    final byStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white54,
          fontSize: 11,
        );
    final authorStyle = byStyle?.copyWith(color: const Color(0xFFE09321));
    final authorTapHandler = onAuthorTap ??
        (String authorName) async {
          final profileUrl = authorProfileUrl?.trim();
          if (profileUrl != null && profileUrl.isNotEmpty) {
            final resolvedUrl = profileUrl.startsWith('http')
                ? profileUrl
                : 'https://www.furaffinity.net$profileUrl';
            await handleFALink(context, resolvedUrl);
            return;
          }
          final encodedAuthor = Uri.encodeComponent(authorName);
          await handleFALink(
            context,
            'https://www.furaffinity.net/user/$encodedAuthor/',
          );
        };

    // Dynamic height (no hardcoding), but still width-constrained to avoid overflows.
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: SizedBox(
        width: maxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (t.isNotEmpty)
              Text(
                t,
                textAlign: TextAlign.center,
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            if (hasAuthor)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'by ', style: byStyle),
                    TextSpan(
                      text: a,
                      style: authorStyle,
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          authorTapHandler(a);
                        },
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Convenience wrapper that composes [FaThumbnailOutline] + [FaThumbnailCaption].
class FaThumbnailDisplay extends StatelessWidget {
  final Widget child;
  final String? rating;
  final String? title;
  final String? author;
  final double borderRadius;
  final double? maxWidth;

  const FaThumbnailDisplay({
    super.key,
    required this.child,
    required this.rating,
    required this.title,
    required this.author,
    this.borderRadius = 8.0,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FaThumbnailOutline(
          rating: rating,
          borderRadius: borderRadius,
          child: child,
        ),
        if (maxWidth != null)
          FaThumbnailCaption(
            maxWidth: maxWidth!,
            title: title,
            author: author,
            authorProfileUrl: null,
          ),
      ],
    );
  }
}
