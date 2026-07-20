import 'package:extended_text/extended_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/comment_tree_painter.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_html/flutter_html.dart';

import 'package:fanotifier/shared/utils/special_text_span_builder.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';

/// Comment display widget extracted from openpost.dart
class CommentWidget extends StatefulWidget {
  final Map<String, dynamic> comment;
  final ValueListenable<CommentTreeLevels> treeLevels;
  final ValueListenable<bool> collapsed;
  final VoidCallback? onToggleCollapse;
  final Duration animationDuration;
  final Curve animationCurve;
  final VoidCallback? onHide;
  final VoidCallback? onEdit;
  final VoidCallback? onReply;
  final VoidCallback? onUnhide;
  final Future<void> Function(String url)? handleLink;
  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final bool Function()? hasAnyCommentSelection;
  final Widget Function(BuildContext, SelectableRegionState)?
      contextMenuBuilder;
  final bool showTranslateButton;
  final VoidCallback? onTranslateToggle;

  const CommentWidget({
    super.key,
    required this.comment,
    required this.treeLevels,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.animationDuration,
    required this.animationCurve,
    this.onHide,
    this.onEdit,
    this.onReply,
    this.onUnhide,
    this.handleLink,
    this.selectionAreaKey,
    this.onSelectionChanged,
    this.hasAnyCommentSelection,
    this.contextMenuBuilder,
    this.showTranslateButton = false,
    this.onTranslateToggle,
  });

  @override
  State<CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  bool _showFullDate = false;
  String? _lastCommentHtml;
  bool _hasHtml = false;
  String _normalizedCommentHtml = '';
  bool _hasActiveSelection = false;
  bool _suppressNextCollapseTap = false;

  @override
  void initState() {
    super.initState();
    _syncHtmlCache();
  }

  @override
  void didUpdateWidget(covariant CommentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncHtmlCache();
  }

  void _syncHtmlCache() {
    final String? commentHtml = widget.comment['commentHtml'];
    if (commentHtml == _lastCommentHtml) return;

    _lastCommentHtml = commentHtml;
    _hasHtml = commentHtml != null && commentHtml.trim().isNotEmpty;
    if (_hasHtml) {
      final String html = commentHtml ?? '';
      _normalizedCommentHtml = normalizeSmilieTokensToHtml(html);
    } else {
      _normalizedCommentHtml = '';
    }
  }

  void _handleCommentSelectionChanged(SelectedContent? content) {
    _hasActiveSelection = content?.plainText.isNotEmpty ?? false;
    widget.onSelectionChanged?.call(content);
  }

  void _handleCommentPointerDown(PointerDownEvent _) {
    _suppressNextCollapseTap =
        _hasActiveSelection || (widget.hasAnyCommentSelection?.call() ?? false);
  }

  void _handleCollapseTap() {
    if (_suppressNextCollapseTap) {
      _suppressNextCollapseTap = false;
      return;
    }
    widget.onToggleCollapse?.call();
  }

  Widget _buildCommentBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: 0.0, right: 0.0, top: 8.0, bottom: 1.0),
      child: Theme(
        data: Theme.of(context).copyWith(
          textSelectionTheme: TextSelectionThemeData(
            selectionColor:
                const Color(0xFFE09321).withValues(alpha: 0.4),
            selectionHandleColor: const Color(0xFFE09321),
          ),
        ),
        child: SelectionArea(
          key: widget.selectionAreaKey,
          onSelectionChanged: _handleCommentSelectionChanged,
          contextMenuBuilder: widget.contextMenuBuilder,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _handleCollapseTap,
            child: _hasHtml
                ? Html(
                  data: _normalizedCommentHtml,
                  onLinkTap: (url, _, __) {
                    if (url != null) {
                      widget.handleLink?.call(url);
                    }
                  },
                  extensions: [
                    faHtmlImageExtension(),
                    TagExtension.inline(
                      tagsToExtend: {'i'},
                      builder: (context) {
                        final assetPath = emojiAssetForSmilieClass(
                            context.attributes['class']);
                        if (assetPath != null) {
                          return WidgetSpan(
                            child: Image.asset(
                              assetPath,
                              width: 20,
                              height: 20,
                            ),
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
                    "body": Style(
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                      color: Colors.grey.shade300,
                      fontSize: FontSize(14),
                    ),
                    ".bbcode_center": Style(
                      display: Display.block,
                      textAlign: TextAlign.center,
                    ),
                    ".bbcode_left": Style(
                      display: Display.block,
                      textAlign: TextAlign.left,
                    ),
                    ".bbcode_right": Style(
                      display: Display.block,
                      textAlign: TextAlign.right,
                    ),
                    "code": Style(
                      backgroundColor: Colors.transparent,
                      padding: HtmlPaddings.zero,
                      margin: Margins.zero,
                      fontFamily: 'inherit',
                      fontSize: FontSize(14),
                      color: Colors.grey.shade300,
                    ),
                    "strong": Style(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade300,
                    ),
                    "em": Style(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade300,
                    ),
                    ".bbcode_u": Style(
                      textDecoration: TextDecoration.underline,
                      color: Colors.grey.shade300,
                    ),
                    "a": Style(
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
                    style:
                        TextStyle(fontSize: 14, color: Colors.grey.shade300),
                ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.comment['deleted'] == true
        ? null
        : _buildCommentBody(context);
    return ValueListenableBuilder<CommentTreeLevels>(
      valueListenable: widget.treeLevels,
      child: body,
      builder: (context, treeLevels, body) {
        return ValueListenableBuilder<bool>(
          valueListenable: widget.collapsed,
          child: body,
          builder: (context, collapsed, body) {
            return _buildComment(
              context,
              treeLevels: treeLevels,
              collapsed: collapsed,
              body: body,
            );
          },
        );
      },
    );
  }

  Widget _buildComment(
    BuildContext context, {
    required CommentTreeLevels treeLevels,
    required bool collapsed,
    required Widget? body,
  }) {
    final double widthPercent = (widget.comment['width'] ?? 100).toDouble();
    final int nestingLevel =
        ((100.0 - widthPercent) / 3.0).round().clamp(0, 4).toInt();
    final double leftPadding = nestingLevel * 16.0;
    final bool isAdmin = widget.comment['isAdmin'] == true;
    final decoration = BoxDecoration(
      gradient: isAdmin
          ? const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF141619),
            Color(0xFF2B3447),
          ],
      )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF101010), Color(0xFF202020)],
            ),
      borderRadius: BorderRadius.circular(8.0),
    );

    if (widget.comment['deleted'] == true) {
      return CustomPaint(
        foregroundPainter: CommentTreePainter(
          nestingLevel: nestingLevel,
          previousNestingLevel: treeLevels.previous,
          nextNestingLevel: treeLevels.next,
        ),
        child: Padding(
          padding: EdgeInsets.only(left: leftPadding, bottom: 6.0),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handleCommentPointerDown,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleCollapseTap,
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
                      onSelectionChanged: _handleCommentSelectionChanged,
                      contextMenuBuilder: widget.contextMenuBuilder,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _handleCollapseTap,
                        child: Text(
                          widget.comment['text'] ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ),
                  ),
                  if (widget.comment['hideLink'] != null)
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
          ),
        ),
      );
    }

    return CustomPaint(
      foregroundPainter: CommentTreePainter(
        nestingLevel: nestingLevel,
        previousNestingLevel: treeLevels.previous,
        nextNestingLevel: treeLevels.next,
      ),
      child: Padding(
        padding: EdgeInsets.only(left: leftPadding, bottom: 6.0),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handleCommentPointerDown,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleCollapseTap,
            child: AnimatedSize(
            duration: widget.animationDuration,
            curve: widget.animationCurve,
            alignment: Alignment.topCenter,
            child: Container(
              padding: EdgeInsets.only(
                  right: 12.0,
                  left: 12.0,
                  top: 8.0,
                  bottom: collapsed ? 10.0 : 2.0),
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
                          final nick = widget.comment['username'];
                          if (nick != null) {
                            Navigator.push(
                              context,
                              UserProfileScreen.route(nickname: nick),
                            );
                          }
                        },
                        child: TweenAnimationBuilder<double>(
                          duration: widget.animationDuration,
                          curve: widget.animationCurve,
                          tween: Tween<double>(
                            begin: collapsed ? 30 : 46,
                            end: collapsed ? 30 : 46,
                          ),
                          builder: (context, avatarSize, _) {
                            return FaNetworkImage(
                              widget.comment['profileImage'],
                              width: avatarSize,
                              height: avatarSize,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) {
                                  return child;
                                }
                                return Image.asset(
                                  'assets/images/defaultpic.gif',
                                  width: avatarSize,
                                  height: avatarSize,
                                  fit: BoxFit.cover,
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  'assets/images/defaultpic.gif',
                                  width: avatarSize,
                                  height: avatarSize,
                                  fit: BoxFit.cover,
                                );
                              },
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
                              ...widget.comment['iconBeforeUrls'].map(
                                (url) {
                                  final isEditedIcon =
                                      url.contains('edited.png');
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
                                },
                              ),
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
                                  child:
                                      FaNetworkImage(url, width: 16, height: 16),
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
                        _animatedSection(
                          visible: !collapsed &&
                              (widget.comment['userTitle'] ?? '').isNotEmpty,
                          child: Text(
                            widget.comment['userTitle'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              _animatedSection(
                visible: !collapsed,
                child: body!,
              ),
              _animatedSection(
                visible: !collapsed,
                child: Row(
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
              ),
            ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _animatedSection({
    required bool visible,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: widget.animationDuration,
      switchInCurve: widget.animationCurve,
      switchOutCurve: widget.animationCurve,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          alignment: const Alignment(-1.0, -1.0),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: visible
          ? KeyedSubtree(
              key: const ValueKey<String>('visible'),
              child: child,
            )
          : const SizedBox.shrink(
              key: ValueKey<String>('hidden'),
            ),
    );
  }
}
