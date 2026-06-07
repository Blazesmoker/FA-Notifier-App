import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:FANotifier/shared/translation/ios_scroll_recovery.dart';
import 'package:FANotifier/shared/translation/native_translate_launcher.dart';
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

              final start =
                  sel.isValid ? math.min(sel.start, sel.end) : text.length;
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

class ReadOnlySelectionContextMenu {
  static Widget Function(BuildContext, SelectableRegionState) builder({
    required String Function() selectedTextProvider,
    bool includeIosTranslate = false,
    IosScrollRecoveryScope? recoveryScope,
  }) {
    return (BuildContext context, SelectableRegionState selectableRegionState) {
      if (!Platform.isIOS || !includeIosTranslate) {
        return AdaptiveTextSelectionToolbar.selectableRegion(
          selectableRegionState: selectableRegionState,
        );
      }

      final items = List<ContextMenuButtonItem>.from(
        selectableRegionState.contextMenuButtonItems,
      );
      final selectedText = selectedTextProvider().trim();

      if (selectedText.isNotEmpty) {
        items.add(
          ContextMenuButtonItem(
            label: _translateLabelForContext(context),
            onPressed: () async {
              final systemLocales =
                  WidgetsBinding.instance.platformDispatcher.locales;
              final localeCode =
                  Localizations.maybeLocaleOf(context)?.languageCode ??
                      (systemLocales.isNotEmpty
                          ? systemLocales.first.languageCode
                          : null) ??
                      'en';
              selectableRegionState.hideToolbar(false);
              final text = selectedTextProvider().trim();
              if (text.isEmpty) return;
              await NativeTranslateLauncher.open(
                text,
                targetLanguageCode: localeCode,
                recoveryScope: recoveryScope,
              );
            },
          ),
        );
      }

      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: selectableRegionState.contextMenuAnchors,
        buttonItems: items,
      );
    };
  }

  static String _translateLabelForContext(BuildContext context) {
    final languageCode =
        Localizations.maybeLocaleOf(context)?.languageCode.toLowerCase() ?? '';
    switch (languageCode) {
      case 'ru':
        return 'Перевести';
      case 'fr':
        return 'Traduire';
      case 'es':
        return 'Traducir';
      case 'de':
        return 'Übersetzen';
      default:
        return 'Translate';
    }
  }
}

class ReadOnlyEditableTextContextMenu {
  static Widget Function(BuildContext, EditableTextState) builder({
    required String Function() selectedTextProvider,
    bool includeIosTranslate = false,
  }) {
    return (BuildContext context, EditableTextState editableTextState) {
      if (!Platform.isIOS || !includeIosTranslate) {
        return AdaptiveTextSelectionToolbar.editableText(
          editableTextState: editableTextState,
        );
      }

      final items = List<ContextMenuButtonItem>.from(
        editableTextState.contextMenuButtonItems,
      );
      final selectedText = selectedTextProvider().trim();

      if (selectedText.isNotEmpty) {
        items.add(
          ContextMenuButtonItem(
            label: ReadOnlySelectionContextMenu._translateLabelForContext(
              context,
            ),
            onPressed: () async {
              final systemLocales =
                  WidgetsBinding.instance.platformDispatcher.locales;
              final localeCode =
                  Localizations.maybeLocaleOf(context)?.languageCode ??
                      (systemLocales.isNotEmpty
                          ? systemLocales.first.languageCode
                          : null) ??
                      'en';
              editableTextState.hideToolbar();
              final text = selectedTextProvider().trim();
              if (text.isEmpty) return;
              await NativeTranslateLauncher.open(
                text,
                targetLanguageCode: localeCode,
              );
            },
          ),
        );
      }

      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: items,
      );
    };
  }
}
