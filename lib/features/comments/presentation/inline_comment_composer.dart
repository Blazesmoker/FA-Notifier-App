import 'dart:async';

import 'package:fanotifier/shared/platform/android_ime_animation.dart';
import 'package:fanotifier/shared/utils/bbcode_context_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

double inlineCommentComposerClearance({
  required int collapsedLines,
  required double viewPaddingBottom,
}) {
  return 72.0 +
      viewPaddingBottom +
      ((collapsedLines - 1).clamp(0, 5).toDouble() * 24.0);
}

class InlineCommentComposer extends StatefulWidget {
  const InlineCommentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.keyboardInset,
    required this.isExpanded,
    required this.collapsedLines,
    required this.hasText,
    required this.showScrollToTop,
    required this.isSending,
    required this.viewPaddingBottom,
    required this.scrollToTopHeroTag,
    required this.onPointerDown,
    required this.onScrollToTop,
    required this.onSend,
    required this.onKeyboardClosing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueListenable<double> keyboardInset;
  final ValueListenable<bool> isExpanded;
  final ValueListenable<int> collapsedLines;
  final ValueListenable<bool> hasText;
  final ValueListenable<bool> showScrollToTop;
  final ValueListenable<bool> isSending;
  final double viewPaddingBottom;
  final String scrollToTopHeroTag;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback onScrollToTop;
  final VoidCallback onSend;
  final VoidCallback onKeyboardClosing;

  @override
  State<InlineCommentComposer> createState() => _InlineCommentComposerState();
}

class _InlineCommentComposerState extends State<InlineCommentComposer> {
  late final ValueNotifier<double> _effectiveKeyboardInset;
  StreamSubscription<AndroidImeAnimationFrame>? _androidImeSubscription;
  late double _lastFlutterKeyboardInset;
  bool _nativeImeAnimating = false;
  bool _nativeImeAvailable = false;
  bool _closingNotificationSent = false;

  @override
  void initState() {
    super.initState();
    _effectiveKeyboardInset = ValueNotifier<double>(widget.keyboardInset.value);
    _lastFlutterKeyboardInset = widget.keyboardInset.value;
    widget.keyboardInset.addListener(_syncFlutterKeyboardInset);
    if (defaultTargetPlatform == TargetPlatform.android) {
      _androidImeSubscription = AndroidImeAnimation.frames.listen(
        _handleAndroidImeFrame,
        onError: _handleAndroidImeError,
        onDone: _handleAndroidImeDone,
      );
    }
  }

  @override
  void didUpdateWidget(covariant InlineCommentComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyboardInset != widget.keyboardInset) {
      oldWidget.keyboardInset.removeListener(_syncFlutterKeyboardInset);
      widget.keyboardInset.addListener(_syncFlutterKeyboardInset);
      _lastFlutterKeyboardInset = widget.keyboardInset.value;
      _syncFlutterKeyboardInset();
    }
  }

  void _handleAndroidImeFrame(AndroidImeAnimationFrame frame) {
    _nativeImeAvailable = true;
    _nativeImeAnimating = frame.isAnimating;
    if (frame.isClosing) {
      if (!_closingNotificationSent) {
        _closingNotificationSent = true;
        widget.onKeyboardClosing();
      }
    } else {
      _closingNotificationSent = false;
    }
    _setEffectiveKeyboardInset(frame.bottom);
  }

  void _handleAndroidImeError(Object error, StackTrace stackTrace) {
    _nativeImeAvailable = false;
    _nativeImeAnimating = false;
    _syncFlutterKeyboardInset();
  }

  void _handleAndroidImeDone() {
    _nativeImeAvailable = false;
    _nativeImeAnimating = false;
    _syncFlutterKeyboardInset();
  }

  void _syncFlutterKeyboardInset() {
    final inset = widget.keyboardInset.value;
    if (defaultTargetPlatform == TargetPlatform.android &&
        !_nativeImeAvailable) {
      final keyboardStartedClosing =
          _lastFlutterKeyboardInset > inset + 0.5;
      if (keyboardStartedClosing && !_closingNotificationSent) {
        _closingNotificationSent = true;
        widget.onKeyboardClosing();
      } else if (inset <= 0.5 || inset > _lastFlutterKeyboardInset + 0.5) {
        _closingNotificationSent = false;
      }
    }
    _lastFlutterKeyboardInset = inset;
    if (!_nativeImeAnimating) {
      _setEffectiveKeyboardInset(inset);
    }
  }

  void _setEffectiveKeyboardInset(double inset) {
    final normalizedInset = inset.clamp(0.0, double.infinity).toDouble();
    if ((normalizedInset - _effectiveKeyboardInset.value).abs() > 0.1) {
      _effectiveKeyboardInset.value = normalizedInset;
    }
  }

  @override
  void dispose() {
    widget.keyboardInset.removeListener(_syncFlutterKeyboardInset);
    _androidImeSubscription?.cancel();
    _effectiveKeyboardInset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _effectiveKeyboardInset,
      child: RepaintBoundary(
        child: _InlineCommentComposerSurface(
          controller: widget.controller,
          focusNode: widget.focusNode,
          isExpanded: widget.isExpanded,
          collapsedLines: widget.collapsedLines,
          hasText: widget.hasText,
          showScrollToTop: widget.showScrollToTop,
          isSending: widget.isSending,
          scrollToTopHeroTag: widget.scrollToTopHeroTag,
          onPointerDown: widget.onPointerDown,
          onScrollToTop: widget.onScrollToTop,
          onSend: widget.onSend,
        ),
      ),
      builder: (context, inset, child) {
        final keyboardOffset = inset + 8.0;
        final bottomOffset =
            inset > 0.5 && keyboardOffset > widget.viewPaddingBottom
                ? keyboardOffset
                : widget.viewPaddingBottom;
        return CustomPaint(
          painter: const _InlineCommentComposerBackgroundPainter(),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomOffset),
            child: child,
          ),
        );
      },
    );
  }
}

class _InlineCommentComposerBackgroundPainter extends CustomPainter {
  const _InlineCommentComposerBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fadeHeight = size.height < 6.0 ? size.height : 6.0;
    if (fadeHeight > 0.0) {
      final fadeRect = Rect.fromLTWH(0.0, 0.0, size.width, fadeHeight);
      final fadePaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(fadeRect);
      canvas.drawRect(fadeRect, fadePaint);
    }
    if (size.height > fadeHeight) {
      canvas.drawRect(
        Rect.fromLTWH(
          0.0,
          fadeHeight,
          size.width,
          size.height - fadeHeight,
        ),
        Paint()..color = Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(_InlineCommentComposerBackgroundPainter oldDelegate) {
    return false;
  }
}

class _InlineCommentComposerSurface extends StatelessWidget {
  const _InlineCommentComposerSurface({
    required this.controller,
    required this.focusNode,
    required this.isExpanded,
    required this.collapsedLines,
    required this.hasText,
    required this.showScrollToTop,
    required this.isSending,
    required this.scrollToTopHeroTag,
    required this.onPointerDown,
    required this.onScrollToTop,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueListenable<bool> isExpanded;
  final ValueListenable<int> collapsedLines;
  final ValueListenable<bool> hasText;
  final ValueListenable<bool> showScrollToTop;
  final ValueListenable<bool> isSending;
  final String scrollToTopHeroTag;
  final ValueChanged<PointerDownEvent> onPointerDown;
  final VoidCallback onScrollToTop;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          isExpanded,
          collapsedLines,
          hasText,
          showScrollToTop,
          isSending,
        ]),
        builder: (context, _) {
          final expanded = isExpanded.value;
          final lines = collapsedLines.value;
          final draftHasText = hasText.value;
          final sending = isSending.value;
          final showScrollButton = showScrollToTop.value;
          final canSend = !sending && draftHasText;
          final fieldLines = expanded ? 6 : lines;
          final isCollapsedSingleLine = !expanded && lines == 1;
          final topPadding = expanded ? 12.0 : 8.0;

          return Row(
            crossAxisAlignment: isCollapsedSingleLine
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.end,
            children: [
              _AnimatedScrollToTopButton(
                visible: showScrollButton && !expanded,
                heroTag: scrollToTopHeroTag,
                onPressed: onScrollToTop,
              ),
              Expanded(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  reverseDuration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    children: [
                      Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: onPointerDown,
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          minLines: fieldLines,
                          maxLines: fieldLines,
                          scrollPadding: const EdgeInsets.only(bottom: 8),
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: const TextStyle(color: Colors.white54),
                            contentPadding: EdgeInsets.fromLTRB(
                              12,
                              topPadding,
                              56,
                              8,
                            ),
                            filled: true,
                            isDense: isCollapsedSingleLine,
                            fillColor: const Color(0xFF151515),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          contextMenuBuilder:
                              BBCodeContextMenu.builder(controller),
                        ),
                      ),
                      if (isCollapsedSingleLine)
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _buildSendButton(
                                canSend: canSend,
                                sending: sending,
                                compact: true,
                              ),
                            ),
                          ),
                        )
                      else
                        Positioned(
                          top: 4,
                          right: 4,
                          child: _buildSendButton(
                            canSend: canSend,
                            sending: sending,
                          ),
                        ),
                      if (expanded && draftHasText && !sending)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white54,
                            ),
                            onPressed: controller.clear,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSendButton({
    required bool canSend,
    required bool sending,
    bool compact = false,
  }) {
    final buttonSize = compact ? 30.0 : 40.0;

    if (sending) {
      return SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton(
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: buttonSize,
        height: buttonSize,
      ),
      visualDensity: VisualDensity.compact,
      icon: Icon(
        Icons.send,
        color: canSend ? const Color(0xFFE09321) : Colors.white54,
      ),
      onPressed: canSend ? onSend : null,
    );
  }
}

class _AnimatedScrollToTopButton extends StatelessWidget {
  const _AnimatedScrollToTopButton({
    required this.visible,
    required this.heroTag,
    required this.onPressed,
  });

  final bool visible;
  final String heroTag;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 210),
        curve: Curves.easeInOut,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: visible ? 44 : 0,
          height: visible ? 36 : 0,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 44,
            maxWidth: 44,
            minHeight: 36,
            maxHeight: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: FloatingActionButton.small(
                    heroTag: heroTag,
                    backgroundColor: const Color(0xFFE09321),
                    elevation: 0,
                    onPressed: onPressed,
                    child: const Icon(Icons.arrow_upward, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
