import 'package:extended_text/extended_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const Map<String, String> kSmilieEmojiAssets = {
  '[smilie-tongue]': 'assets/emojis/tongue.png',
  '[smilie-evil]': 'assets/emojis/evil.png',
  '[smilie-lmao]': 'assets/emojis/lmao.png',
  '[smilie-gift]': 'assets/emojis/gift.png',
  '[smilie-derp]': 'assets/emojis/derp.png',
  '[smilie-teeth]': 'assets/emojis/teeth.png',
  '[smilie-cool]': 'assets/emojis/cool.png',
  '[smilie-huh]': 'assets/emojis/huh.png',
  '[smilie-cd]': 'assets/emojis/cd.png',
  '[smilie-coffee]': 'assets/emojis/coffee.png',
  '[smilie-sarcastic]': 'assets/emojis/sarcastic.png',
  '[smilie-veryhappy]': 'assets/emojis/veryhappy.png',
  '[smilie-wink]': 'assets/emojis/wink.png',
  '[smilie-whatever]': 'assets/emojis/whatever.png',
  '[smilie-crying]': 'assets/emojis/crying.png',
  '[smilie-love]': 'assets/emojis/love.png',
  '[smilie-serious]': 'assets/emojis/serious.png',
  '[smilie-yelling]': 'assets/emojis/yelling.png',
  '[smilie-oooh]': 'assets/emojis/oooh.png',
  '[smilie-angel]': 'assets/emojis/angel.png',
  '[smilie-dunno]': 'assets/emojis/dunno.png',
  '[smilie-nerd]': 'assets/emojis/nerd.png',
  '[smilie-sad]': 'assets/emojis/sad.png',
  '[smilie-zipped]': 'assets/emojis/zipped.png',
  '[smilie-smile]': 'assets/emojis/smile.png',
  '[smilie-badhairday]': 'assets/emojis/badhairday.png',
  '[smilie-embarrassed]': 'assets/emojis/embarrassed.png',
  '[smilie-note]': 'assets/emojis/note.png',
  '[smilie-sleepy]': 'assets/emojis/sleepy.png',
};

String normalizeSmilieTokensToHtml(String html) {
  return html.replaceAllMapped(
    RegExp(r'\[smilie-([a-z0-9]+)\]', caseSensitive: false),
    (match) {
      final name = match.group(1)!.toLowerCase();
      final token = '[smilie-$name]';
      if (!kSmilieEmojiAssets.containsKey(token)) {
        return match.group(0)!;
      }
      return '<i class="smilie $name"></i>';
    },
  );
}

String? emojiAssetForSmilieClass(String? classAttr) {
  if (classAttr == null || classAttr.trim().isEmpty) {
    return null;
  }
  final normalizedClass =
      classAttr.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (!normalizedClass.startsWith('smilie ')) {
    return null;
  }
  final token = '[${normalizedClass.replaceAll(' ', '-')}]';
  return kSmilieEmojiAssets[token];
}

class EmojiSpecialTextSpanBuilder extends SpecialTextSpanBuilder {
  final Map<String, String> emojiMapping = kSmilieEmojiAssets;

  final void Function(String)? onTapLink;

  EmojiSpecialTextSpanBuilder({this.onTapLink});

  @override
  SpecialText? createSpecialText(String flag,
      {TextStyle? textStyle,
      SpecialTextGestureTapCallback? onTap,
      int? index}) {
    return null;
  }

  @override
  TextSpan build(String data,
      {TextStyle? textStyle, SpecialTextGestureTapCallback? onTap}) {
    final spans = <InlineSpan>[];

    // Matches, in order:
    // 1) [[i]]...[[/i]] or [[b]]...[[/b]] or [[u]]...[[/u]]
    //    group1 = marker (i|b|u), group2 = inner text
    // 2) [smilie-...]
    // 3) http(s):// links
    final regex = RegExp(
      r'(?:\[\[(i|b|u)\]\](.*?)\[\[\/\1\]\])|(\[smilie-[^\]]+\])|(https?:\/\/[^\s]+)',
      dotAll: true,
      caseSensitive: false,
    );

    int currentIndex = 0;

    for (final match in regex.allMatches(data)) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: data.substring(currentIndex, match.start),
          style: textStyle,
        ));
      }

      if (match.group(1) != null) {
        // Style markers: [[i]] / [[b]] / [[u]]
        final marker = match.group(1)!.toLowerCase();
        final inner = match.group(2) ?? '';
        TextStyle mergeStyle;
        switch (marker) {
          case 'b':
            mergeStyle = const TextStyle(fontWeight: FontWeight.bold);
            break;
          case 'u':
            mergeStyle = const TextStyle(decoration: TextDecoration.underline);
            break;
          case 'i':
          default:
            mergeStyle = const TextStyle(fontStyle: FontStyle.italic);
            break;
        }
        // Re-run builder on inner to keep emojis/links and allow nested styles
        spans.add(build(
          inner,
          textStyle: (textStyle ?? const TextStyle()).merge(mergeStyle),
          onTap: onTap,
        ));
      } else if (match.group(3) != null) {
        // Emoji placeholder: [smilie-...]
        final emojiKey = match.group(3)!;
        final asset = emojiMapping[emojiKey];
        if (asset != null) {
          spans.add(ExtendedWidgetSpan(
            child: Image.asset(asset, width: 20, height: 20),
            actualText: emojiKey,
          ));
        } else {
          spans.add(TextSpan(text: emojiKey, style: textStyle));
        }
      } else if (match.group(4) != null) {
        // URL
        final url = match.group(4)!;
        spans.add(TextSpan(
          text: url,
          style:
              (textStyle ?? const TextStyle()).copyWith(color: Colors.orange),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (onTapLink != null) onTapLink!(url);
            },
        ));
      }

      currentIndex = match.end;
    }

    if (currentIndex < data.length) {
      spans.add(TextSpan(
        text: data.substring(currentIndex),
        style: textStyle,
      ));
    }

    return TextSpan(children: spans, style: textStyle);
  }
}
