import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/utils/comment_composer_lines.dart';

class CommentComposerController {
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  final ValueNotifier<bool> _isExpanded = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _hasText = ValueNotifier<bool>(false);
  final ValueNotifier<int> _collapsedLines = ValueNotifier<int>(1);
  bool _commentComposerFocusRequestedByUser = false;
  bool _blockRestoredCommentComposerFocus = true;

  ValueListenable<bool> get isExpanded => _isExpanded;
  ValueListenable<bool> get hasText => _hasText;
  ValueListenable<int> get collapsedLines => _collapsedLines;

  void initialize() {
    textController.addListener(_onDraftChanged);
    focusNode.addListener(_syncExpansion);
    _onDraftChanged();
  }

  void dispose() {
    textController.removeListener(_onDraftChanged);
    textController.dispose();
    focusNode.dispose();
    _isExpanded.dispose();
    _hasText.dispose();
    _collapsedLines.dispose();
  }

  void _syncExpansion() {
    final shouldExpand = focusNode.hasFocus;
    if (shouldExpand &&
        _blockRestoredCommentComposerFocus &&
        !_commentComposerFocusRequestedByUser) {
      dismissFocus();
      return;
    }
    if (shouldExpand != _isExpanded.value) {
      _isExpanded.value = shouldExpand;
    }
    if (shouldExpand) {
      _commentComposerFocusRequestedByUser = false;
      _blockRestoredCommentComposerFocus = false;
    } else {
      _commentComposerFocusRequestedByUser = false;
      _blockRestoredCommentComposerFocus = true;
    }
  }

  void armFocusGuard() {
    _commentComposerFocusRequestedByUser = false;
    _blockRestoredCommentComposerFocus = true;
  }

  void _allowFocusFromUser() {
    _commentComposerFocusRequestedByUser = true;
    _blockRestoredCommentComposerFocus = false;
  }

  void handlePointerDown(PointerDownEvent event) {
    _allowFocusFromUser();
  }

  void dismissFocus() {
    armFocusGuard();
    if (focusNode.hasFocus) {
      focusNode.unfocus();
    }
  }

  void _onDraftChanged() {
    final bool hasText = textController.text.trim().isNotEmpty;
    if (hasText != _hasText.value) {
      _hasText.value = hasText;
    }

    final int collapsedLines = collapsedComposerLines(textController.text);
    if (collapsedLines != _collapsedLines.value) {
      _collapsedLines.value = collapsedLines;
    }
  }
}
