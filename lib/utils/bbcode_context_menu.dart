// lib/utils/bbcode_context_menu.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// BBCode-aware context menu with formatting buttons and selective platform items
class BBCodeContextMenu {
  static Widget Function(BuildContext, EditableTextState) builder(
      TextEditingController controller, {
        List<String> tags = const ['b', 'i', 'u', 'left', 'center', 'right'],
        Map<String, String>? customLabels,
        bool includeTranslate = true, // Only include translate button
      }) {
    return (BuildContext context, EditableTextState editableTextState) {
      final hasSelection = !editableTextState.textEditingValue.selection.isCollapsed;

      void hideToolbar() {
        try {
          editableTextState.hideToolbar();
        } catch (_) {}
      }

      // Helper to wrap selection with BBCode tags
      void wrapSelection(String tag) {
        final sel = controller.selection;
        if (!sel.isValid || sel.isCollapsed) return;

        final start = math.min(sel.start, sel.end);
        final end = math.max(sel.start, sel.end);
        final selected = controller.text.substring(start, end);
        final open = '[$tag]';
        final close = '[/$tag]';

        final newText = controller.text.replaceRange(
          start,
          end,
          '$open$selected$close',
        );

        controller.value = controller.value.copyWith(
          text: newText,
          selection: TextSelection.collapsed(
            offset: start + open.length + selected.length,
          ),
          composing: TextRange.empty,
        );

        hideToolbar();
      }

      final items = <ContextMenuButtonItem>[];

      // Standard editing buttons
      if (hasSelection) {
        items.addAll([
          ContextMenuButtonItem(
            label: 'Copy',
            onPressed: () async {
              final sel = controller.selection;
              if (!sel.isValid || sel.isCollapsed) return;

              final start = math.min(sel.start, sel.end);
              final end = math.max(sel.start, sel.end);
              final selText = controller.text.substring(start, end);

              await Clipboard.setData(ClipboardData(text: selText));
              hideToolbar();
            },
          ),
          ContextMenuButtonItem(
            label: 'Cut',
            onPressed: () async {
              final sel = controller.selection;
              if (!sel.isValid || sel.isCollapsed) return;

              final start = math.min(sel.start, sel.end);
              final end = math.max(sel.start, sel.end);
              final selText = controller.text.substring(start, end);

              await Clipboard.setData(ClipboardData(text: selText));

              controller.value = controller.value.copyWith(
                text: controller.text.replaceRange(start, end, ''),
                selection: TextSelection.collapsed(offset: start),
                composing: TextRange.empty,
              );

              hideToolbar();
            },
          ),
        ]);
      }

      items.add(ContextMenuButtonItem(
        label: 'Paste',
        onPressed: () async {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          final paste = data?.text ?? '';

          final sel = controller.selection;
          final text = controller.text;
          final int start = sel.isValid ? math.min(sel.start, sel.end) : text.length;
          final int end = sel.isValid ? math.max(sel.start, sel.end) : start;

          controller.value = controller.value.copyWith(
            text: text.replaceRange(start, end, paste),
            selection: TextSelection.collapsed(offset: start + paste.length),
            composing: TextRange.empty,
          );

          hideToolbar();
        },
      ));

      // Add BBCode formatting buttons when text is selected
      if (hasSelection) {
        for (final tag in tags) {
          items.add(ContextMenuButtonItem(
            label: customLabels?[tag] ?? _defaultLabelForTag(tag),
            onPressed: () => wrapSelection(tag),
          ));
        }
      }

      // Add only Translate button from platform items
      if (includeTranslate) {
        final platformItems = editableTextState.contextMenuButtonItems;

        // Find translate button (works in multiple languages)
        final translateItem = platformItems.firstWhere(
              (item) {
            final label = item.label?.toLowerCase() ?? '';
            return label.contains('translate') ||
                label.contains('перевести') || // Russian
                label.contains('traduire') ||  // French
                label.contains('traducir') ||  // Spanish
                label.contains('übersetzen'); // German
          },
          orElse: () => ContextMenuButtonItem(
            label: '',
            onPressed: () {},
          ),
        );


        if (translateItem.label?.isNotEmpty ?? false) {
          items.add(translateItem);
          debugPrint('Added translate button: ${translateItem.label}');
        } else {
          debugPrint('Translate button not found');
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