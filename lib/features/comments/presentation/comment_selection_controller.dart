import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

class CommentSelectionController {
  CommentSelectionController({required this._otherSelectionKeys});

  final List<GlobalKey<SelectionAreaState>> _otherSelectionKeys;
  final Map<Object, GlobalKey<SelectionAreaState>> _commentSelectionKeys =
      <Object, GlobalKey<SelectionAreaState>>{};
  final Map<Object, String> _commentSelectedTexts = <Object, String>{};
  int? _selectionClearPointerId;
  Offset? _selectionClearPointerDownPosition;
  DateTime? _selectionClearPointerDownTime;
  bool _selectionClearPointerMoved = false;

  bool get hasSelection => _commentSelectedTexts.isNotEmpty;

  Object commentSelectionId(Map<String, dynamic> comment, int index) {
    return comment['commentId']?.toString() ?? 'comment_$index';
  }

  GlobalKey<SelectionAreaState> commentSelectionKeyFor(Object selectionId) {
    return _commentSelectionKeys.putIfAbsent(
      selectionId,
      () => GlobalKey<SelectionAreaState>(),
    );
  }

  String selectedCommentTextFor(Object selectionId) {
    return _commentSelectedTexts[selectionId] ?? '';
  }

  void updateCommentSelectedText(Object selectionId, SelectedContent? content) {
    final text = content?.plainText ?? '';
    if (text.isEmpty) {
      _commentSelectedTexts.remove(selectionId);
      return;
    }
    _commentSelectedTexts[selectionId] = text;
  }

  void _clearSelectionArea(GlobalKey<SelectionAreaState> key) {
    final state = key.currentState;
    if (state == null) return;
    state.selectableRegion.clearSelection();
    state.selectableRegion.hideToolbar();
  }

  void clearAllTextSelections() {
    for (final key in _otherSelectionKeys) {
      _clearSelectionArea(key);
    }
    for (final key in _commentSelectionKeys.values) {
      _clearSelectionArea(key);
    }
  }

  void handleSelectionClearPointerDown(PointerDownEvent event) {
    _selectionClearPointerId = event.pointer;
    _selectionClearPointerDownPosition = event.position;
    _selectionClearPointerDownTime = DateTime.now();
    _selectionClearPointerMoved = false;
  }

  void handleSelectionClearPointerMove(PointerMoveEvent event) {
    if (_selectionClearPointerId != event.pointer ||
        _selectionClearPointerDownPosition == null) {
      return;
    }
    if ((event.position - _selectionClearPointerDownPosition!).distance > 10) {
      _selectionClearPointerMoved = true;
    }
  }

  void handleSelectionClearPointerUp(PointerUpEvent event) {
    if (_selectionClearPointerId != event.pointer) return;
    final downTime = _selectionClearPointerDownTime;
    final isQuickTap =
        downTime != null &&
        DateTime.now().difference(downTime) <=
            const Duration(milliseconds: 250);
    if (!_selectionClearPointerMoved && isQuickTap) {
      clearAllTextSelections();
    }
    _resetSelectionClearPointer();
  }

  void handleSelectionClearPointerCancel(PointerCancelEvent event) {
    if (_selectionClearPointerId != event.pointer) return;
    _resetSelectionClearPointer();
  }

  void _resetSelectionClearPointer() {
    _selectionClearPointerId = null;
    _selectionClearPointerDownPosition = null;
    _selectionClearPointerDownTime = null;
    _selectionClearPointerMoved = false;
  }
}
