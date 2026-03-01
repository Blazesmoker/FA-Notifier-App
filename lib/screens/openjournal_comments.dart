import 'package:extended_text/extended_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' as fh;
import '../utils/specialTextSpanBuilder.dart';
import 'user_profile_screen.dart';

/// Comment UI extracted from openjournal.dart
class CommentWidget extends StatefulWidget {
  final Map<String, dynamic> comment;
  final VoidCallback? onHide;
  final VoidCallback? onEdit;
  final VoidCallback? onReply;
  final VoidCallback? onUnhide;
  final Future<void> Function(String url)? handleLink;

  const CommentWidget({
    Key? key,
    required this.comment,
    this.onHide,
    this.onEdit,
    this.onReply,
    this.onUnhide,
    this.handleLink,
  }) : super(key: key);

  @override
  _CommentWidgetState createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  bool _showFullDate = false;

  @override
  Widget build(BuildContext context) {
    double widthPercent = (widget.comment['width'] ?? 100).toDouble();
    int nestingLevel = ((100.0 - widthPercent) / 3.0).round().clamp(0, 4);
    double leftPadding = nestingLevel * 16.0;
    final String? commentHtml = widget.comment['commentHtml'];
    final bool hasHtml = commentHtml != null && commentHtml.trim().isNotEmpty;
    final String normalizedCommentHtml =
        hasHtml ? normalizeSmilieTokensToHtml(commentHtml) : '';
    if (widget.comment['deleted'] == true) {
      return Padding(
        padding: EdgeInsets.only(left: leftPadding, bottom: 6.0),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.comment['text'] ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
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
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: leftPadding, bottom: 6.0),
      child: Container(
        padding: const EdgeInsets.only(
            right: 12.0, left: 12.0, top: 8.0, bottom: 2.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0b0b0b), Color(0xFF202020)],
          ),
          borderRadius: BorderRadius.circular(8.0),
        ),
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
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                nickname: widget.comment['username'],
                              ),
                            ),
                          );
                        }
                      },
                      child: Image.network(
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
                                child: Image.network(
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
                                child: Image.network(
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
                    selectionColor: const Color(0xFFE09321).withOpacity(0.4),
                    selectionHandleColor: const Color(0xFFE09321),
                  ),
                ),
                child: hasHtml
                    ? fh.Html(
                        data: normalizedCommentHtml,
                        onLinkTap: (url, _, __) {
                          if (url != null) {
                            widget.handleLink?.call(url);
                          }
                        },
                        extensions: [
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
                              style:
                                  TextStyle(color: Colors.white, fontSize: 14)),
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
    );
  }
}
