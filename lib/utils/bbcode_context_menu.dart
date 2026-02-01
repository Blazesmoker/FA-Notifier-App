import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cross-platform BBCode-aware context menu
/// Safe for BOTH Android and iOS (no native crashes)
class BBCodeContextMenu {
  static Widget Function(BuildContext, EditableTextState) builder(
      TextEditingController controller, {
        List<String> tags = const ['b', 'i', 'u', 'left', 'center', 'right'],
        Map<String, String>? customLabels,
        bool includeTranslate = true,
      }) {
    return (BuildContext context, EditableTextState editableTextState) {
      final selection = editableTextState.textEditingValue.selection;
      final hasSelection = selection.isValid && !selection.isCollapsed;

      void hideToolbar() {
        try {
          editableTextState.hideToolbar();
        } catch (_) {}
      }

      /// iOS-safe delayed execution
      void runAfterToolbarHidden(VoidCallback action) {
        hideToolbar();

        if (Platform.isIOS) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            action();
          });
        } else {
          action();
        }
      }

      void wrapSelection(String tag) {
        final sel = controller.selection;
        if (!sel.isValid || sel.isCollapsed) return;

        final start = math.min(sel.start, sel.end);
        final end = math.max(sel.start, sel.end);

        final selectedText = controller.text.substring(start, end);
        final open = '[$tag]';
        final close = '[/$tag]';

        controller.value = controller.value.copyWith(
          text: controller.text.replaceRange(
            start,
            end,
            '$open$selectedText$close',
          ),
          selection: TextSelection.collapsed(
            offset: start + open.length + selectedText.length,
          ),
          composing: TextRange.empty,
        );
      }

      final List<ContextMenuButtonItem> items = [];

      // ---- Standard editing actions ----

      if (hasSelection) {
        items.addAll([
          ContextMenuButtonItem(
            label: 'Copy',
            onPressed: () {
              runAfterToolbarHidden(() async {
                final sel = controller.selection;
                if (!sel.isValid || sel.isCollapsed) return;

                final start = math.min(sel.start, sel.end);
                final end = math.max(sel.start, sel.end);
                final text = controller.text.substring(start, end);

                await Clipboard.setData(ClipboardData(text: text));
              });
            },
          ),
          ContextMenuButtonItem(
            label: 'Cut',
            onPressed: () {
              runAfterToolbarHidden(() async {
                final sel = controller.selection;
                if (!sel.isValid || sel.isCollapsed) return;

                final start = math.min(sel.start, sel.end);
                final end = math.max(sel.start, sel.end);
                final text = controller.text.substring(start, end);

                await Clipboard.setData(ClipboardData(text: text));

                controller.value = controller.value.copyWith(
                  text: controller.text.replaceRange(start, end, ''),
                  selection: TextSelection.collapsed(offset: start),
                  composing: TextRange.empty,
                );
              });
            },
          ),
        ]);
      }

      items.add(
        ContextMenuButtonItem(
          label: 'Paste',
          onPressed: () {
            runAfterToolbarHidden(() async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final paste = data?.text ?? '';

              final sel = controller.selection;
              final text = controller.text;

              final start = sel.isValid ? math.min(sel.start, sel.end) : text.length;
              final end = sel.isValid ? math.max(sel.start, sel.end) : start;

              controller.value = controller.value.copyWith(
                text: text.replaceRange(start, end, paste),
                selection: TextSelection.collapsed(
                  offset: start + paste.length,
                ),
                composing: TextRange.empty,
              );
            });
          },
        ),
      );

      // ---- BBCode formatting ----

      if (hasSelection) {
        for (final tag in tags) {
          items.add(
            ContextMenuButtonItem(
              label: customLabels?[tag] ?? _defaultLabelForTag(tag),
              onPressed: () {
                runAfterToolbarHidden(() {
                  wrapSelection(tag);
                });
              },
            ),
          );
        }
      }

      // ---- Platform Translate button (optional) ----

      if (includeTranslate) {
        final platformItems = editableTextState.contextMenuButtonItems;

        final translateItem = platformItems.firstWhere(
              (item) {
            final label = item.label?.toLowerCase() ?? '';
            return label.contains('translate') ||
                label.contains('перевести') ||
                label.contains('traduire') ||
                label.contains('traducir') ||
                label.contains('übersetzen');
          },
          orElse: () => ContextMenuButtonItem(
            label: '',
            onPressed: () {},
          ),
        );

        if (translateItem.label?.isNotEmpty ?? false) {
          items.add(translateItem);
        }
      }

      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: items,
      );
    };
  }

  static String _defaultLabelForTag(String tag) {
    switch (tag) {
      case 'b':
        return 'Bold';
      case 'i':
        return 'Italic';
      case 'u':
        return 'Underline';
      case 'left':
        return 'Align Left';
      case 'center':
        return 'Align Center';
      case 'right':
        return 'Align Right';
      case 'spoiler':
        return 'Spoiler';
      case 'url':
        return 'Link';
      default:
        return tag.toUpperCase();
    }
  }
}
