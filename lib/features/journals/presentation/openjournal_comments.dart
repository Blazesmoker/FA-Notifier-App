import 'package:extended_text/extended_text.dart';
import 'package:flutter/material.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_html/flutter_html.dart' as fh;

import 'package:FANotifier/shared/utils/specialTextSpanBuilder.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_screen.dart';

/// Comment UI extracted from openjournal.dart
class CommentWidget extends StatefulWidget {
  final Map<String, dynamic> comment;
  final int previousNestingLevel;
  final int nextNestingLevel;
  final VoidCallback? onHide;
  final VoidCallback? onEdit;
  final VoidCallback? onReply;
  final VoidCallback? onUnhide;
  final Future<void> Function(String url)? handleLink;
  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final Widget Function(BuildContext, SelectableRegionState)?
      contextMenuBuilder;
  final bool showTranslateButton;
  final VoidCallback? onTranslateToggle;

  const CommentWidget({
    Key? key,
    required this.comment,
    required this.previousNestingLevel,
    required this.nextNestingLevel,
    this.onHide,
    this.onEdit,
    this.onReply,
    this.onUnhide,
    this.handleLink,
    this.selectionAreaKey,
    this.onSelectionChanged,
    this.contextMenuBuilder,
    this.showTranslateButton = false,
    this.onTranslateToggle,
  }) : super(key: key);

  @override
  _CommentWidgetState createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  bool _showFullDate = false;

  @override
  Widget build(BuildContext context) {
    final double widthPercent = (widget.comment['width'] ?? 100).toDouble();
    final int nestingLevel =
        ((100.0 - widthPercent) / 3.0).round().clamp(0, 4).toInt();
    final double leftPadding = nestingLevel * 16.0;
    final String? commentHtml = widget.comment['commentHtml'];
    final bool hasHtml =
        commentHtml != null && commentHtml.trim().isNotEmpty;
    final String normalizedCommentHtml =
        hasHtml ? normalizeSmilieTokensToHtml(commentHtml) : '';
    final decoration = BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF101010), Color(0xFF202020)],
      ),
      borderRadius: BorderRadius.circular(8.0),
    );

    if (widget.comment['deleted'] == true) {
      return CustomPaint(
        foregroundPainter: _CommentTreePainter(
          nestingLevel: nestingLevel,
          previousNestingLevel: widget.previousNestingLevel,
          nextNestingLevel: widget.nextNestingLevel,
        ),
        child: Padding(
          padding: EdgeInsets.only(left: leftPadding, bottom: 6.0),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
            decoration: decoration,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SelectionArea(
                    key: widget.selectionAreaKey,
                    onSelectionChanged: widget.onSelectionChanged,
                    contextMenuBuilder: widget.contextMenuBuilder,
                    child: Text(
                      widget.comment['text'] ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ),
                if (widget.onUnhide != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: widget.onUnhide,
                    child: const Text(
                      'Unhide',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return CustomPaint(
      foregroundPainter: _CommentTreePainter(
        nestingLevel: nestingLevel,
        previousNestingLevel: widget.previousNestingLevel,
        nextNestingLevel: widget.nextNestingLevel,
      ),
      child: Padding(
        padding: EdgeInsets.only(left: leftPadding, bottom: 6.0),
        child: Container(
          padding: const EdgeInsets.only(
              right: 12.0, left: 12.0, top: 8.0, bottom: 2.0),
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.comment['profileImage'] != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                      child: GestureDetector(
                        onTap: () {
                          if (widget.comment['username'] != null) {
                            Navigator.push(
                              context,
                              UserProfileScreen.route(
                                nickname: widget.comment['username'],
                              ),
                            );
                          }
                        },
                        child: FaNetworkImage(
                          widget.comment['profileImage'],
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) {
                              return child;
                            }
                            return Image.asset(
                              'assets/images/defaultpic.gif',
                              width: 46,
                              height: 46,
                              fit: BoxFit.cover,
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Image.asset(
                              'assets/images/defaultpic.gif',
                              width: 46,
                              height: 46,
                              fit: BoxFit.cover,
                            );
                          },
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (widget.comment['iconBeforeUrls'] != null &&
                                widget.comment['iconBeforeUrls'].isNotEmpty)
                              ...widget.comment['iconBeforeUrls'].map((url) {
                                final isEditedIcon = url.contains('edited.png');
                                return Padding(
                                  padding: const EdgeInsets.only(right: 4.0),
                                  child: FaNetworkImage(
                                    url,
                                    width: 16,
                                    height: 16,
                                    color: isEditedIcon ? Colors.white : null,
                                    colorBlendMode:
                                        isEditedIcon ? BlendMode.srcIn : null,
                                  ),
                                );
                              }),
                            Flexible(
                              child: Text(
                                widget.comment['displayName'] ??
                                    widget.comment['username'] ??
                                    'Anonymous',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.comment['iconAfterUrls'] != null &&
                                widget.comment['iconAfterUrls'].isNotEmpty)
                              ...widget.comment['iconAfterUrls'].map(
                                (url) => Padding(
                                  padding: const EdgeInsets.only(left: 4.0),
                                  child: FaNetworkImage(
                                    url,
                                    width: 16,
                                    height: 16,
                                  ),
                                ),
                              ),
                            if (widget.comment['isOP'] == true)
                              const Padding(
                                padding: EdgeInsets.only(left: 4.0),
                                child: Text(
                                  'OP',
                                  style: TextStyle(
                                    color: Color(0xFFE09321),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          '${widget.comment['symbol'] ?? '~'}${widget.comment['username'] ?? 'Anonymous'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFE09321),
                          ),
                        ),
                        if ((widget.comment['userTitle'] ?? '').isNotEmpty)
                          Text(
                            widget.comment['userTitle'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(
                    left: 0.0, right: 8.0, top: 11.0, bottom: 1.0),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      selectionColor: const Color(0xFFE09321).withValues(alpha: 0.4),
                      selectionHandleColor: const Color(0xFFE09321),
                    ),
                  ),
                  child: SelectionArea(
                    key: widget.selectionAreaKey,
                    onSelectionChanged: widget.onSelectionChanged,
                    contextMenuBuilder: widget.contextMenuBuilder,
                    child: hasHtml
                        ? fh.Html(
                            data: normalizedCommentHtml,
                            onLinkTap: (url, _, __) {
                              if (url != null) {
                                widget.handleLink?.call(url);
                              }
                            },
                            extensions: [
                              faHtmlImageExtension(),
                              fh.TagExtension.inline(
                                tagsToExtend: {'i'},
                                builder: (context) {
                                  final assetPath = emojiAssetForSmilieClass(
                                      context.attributes['class']);
                                  if (assetPath != null) {
                                    return WidgetSpan(
                                      child: Image.asset(assetPath,
                                          width: 20, height: 20),
                                    );
                                  }
                                  return TextSpan(
                                    style: const TextStyle(
                                        fontStyle: FontStyle.italic),
                                    children: context.inlineSpanChildren ??
                                        const <InlineSpan>[],
                                  );
                                },
                              ),
                            ],
                            style: {
                              "body": fh.Style(
                                margin: fh.Margins.zero,
                                padding: fh.HtmlPaddings.zero,
                                color: Colors.grey.shade300,
                                fontSize: fh.FontSize(14),
                              ),
                              ".bbcode_center": fh.Style(
                                display: fh.Display.block,
                                textAlign: TextAlign.center,
                              ),
                              ".bbcode_left": fh.Style(
                                display: fh.Display.block,
                                textAlign: TextAlign.left,
                              ),
                              ".bbcode_right": fh.Style(
                                display: fh.Display.block,
                                textAlign: TextAlign.right,
                              ),
                              "code": fh.Style(
                                backgroundColor: Colors.transparent,
                                padding: fh.HtmlPaddings.zero,
                                margin: fh.Margins.zero,
                                fontFamily: 'inherit',
                                fontSize: fh.FontSize(14),
                                color: Colors.grey.shade300,
                              ),
                              "strong": fh.Style(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade300,
                              ),
                              "em": fh.Style(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey.shade300,
                              ),
                              ".bbcode_u": fh.Style(
                                textDecoration: TextDecoration.underline,
                                color: Colors.grey.shade300,
                              ),
                              "a": fh.Style(
                                color: const Color(0xFFE09321),
                                textDecoration: TextDecoration.none,
                              ),
                            },
                          )
                        : ExtendedText(
                            widget.comment['text'] ?? '',
                            specialTextSpanBuilder: EmojiSpecialTextSpanBuilder(
                              onTapLink: widget.handleLink,
                            ),
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade300),
                          ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _showFullDate = !_showFullDate;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: ClipRect(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _showFullDate
                                  ? (widget.comment['popupDateFull'] ??
                                      widget.comment['popupDateRelative'] ??
                                      '')
                                  : (widget.comment['popupDateRelative'] ?? ''),
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.comment['hideLink'] != null)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.visibility_off,
                              size: 16, color: Colors.white),
                          onPressed: widget.onHide,
                        ),
                      if (widget.comment['editLink'] != null)
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.only(left: 4.0, right: 8),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: widget.onEdit,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.edit, size: 16, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Edit',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 14)),
                            ],
                          ),
                        ),
                      if (widget.showTranslateButton)
                        IconButton(
                          padding: const EdgeInsets.only(left: 2, right: 4),
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: 'Translate',
                          icon: const Icon(
                            Icons.g_translate,
                            size: 18,
                            color: Colors.white,
                          ),
                          onPressed: widget.onTranslateToggle,
                        ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.only(left: 6),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: widget.onReply,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.reply, size: 19, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Reply',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentTreePainter extends CustomPainter {
  final int nestingLevel;
  final int previousNestingLevel;
  final int nextNestingLevel;

  const _CommentTreePainter({
    required this.nestingLevel,
    required this.previousNestingLevel,
    required this.nextNestingLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nestingLevel <= 0) {
      return;
    }

    const indentWidth = 16.0;
    const lineWidth = 3.0;
    const bottomSpacing = 6.0;
    final paint = Paint()
      ..color = const Color(0xFF1C1B1B)
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    final contentHeight =
        (size.height - bottomSpacing).clamp(0.0, size.height).toDouble();
    final currentX = nestingLevel * indentWidth - (indentWidth / 2);
    final topJoinY = -bottomSpacing;

    for (int level = 1; level < nestingLevel; level++) {
      final x = level * indentWidth - (indentWidth / 2);
      final startY = previousNestingLevel >= level ? topJoinY : 0.0;
      final endY = nextNestingLevel >= level ? size.height : contentHeight;
      if (endY <= startY) {
        continue;
      }
      canvas.drawLine(
        Offset(x, startY),
        Offset(x, endY),
        paint,
      );
    }

    final currentEndY =
        nextNestingLevel >= nestingLevel ? size.height : contentHeight;
    if (currentEndY > topJoinY) {
      canvas.drawLine(
        Offset(currentX, topJoinY),
        Offset(currentX, currentEndY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CommentTreePainter oldDelegate) {
    return oldDelegate.nestingLevel != nestingLevel ||
        oldDelegate.previousNestingLevel != previousNestingLevel ||
        oldDelegate.nextNestingLevel != nextNestingLevel;
  }
}
