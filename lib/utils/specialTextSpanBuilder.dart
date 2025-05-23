import 'package:extended_text/extended_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class EmojiSpecialTextSpanBuilder extends SpecialTextSpanBuilder {
  final Map<String, String> emojiMapping = {
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


  final void Function(String)? onTapLink;

  EmojiSpecialTextSpanBuilder({this.onTapLink});
  @override
  SpecialText? createSpecialText(String flag,
      {TextStyle? textStyle, SpecialTextGestureTapCallback? onTap, int? index}) {
    return null;
  }


  @override
  TextSpan build(String data, {TextStyle? textStyle, SpecialTextGestureTapCallback? onTap}) {
    List<InlineSpan> spans = [];
    RegExp regex = RegExp(r'(\[smilie-[^\]]+\])|(https?:\/\/[^\s]+)');
    int currentIndex = 0;

    for (final Match match in regex.allMatches(data)) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: data.substring(currentIndex, match.start),
          style: textStyle,
        ));
      }
      if (match.group(1) != null) {
        String emojiKey = match.group(1)!;
        if (emojiMapping.containsKey(emojiKey)) {
          spans.add(ExtendedWidgetSpan(
            child: Image.asset(
              emojiMapping[emojiKey]!,
              width: 20,
              height: 20,
            ),
            actualText: emojiKey,
          ));
        } else {
          spans.add(TextSpan(text: emojiKey, style: textStyle));
        }
      }

      else if (match.group(2) != null) {
        String url = match.group(2)!;
        spans.add(TextSpan(
          text: url,
          style: textStyle?.copyWith(color: Colors.orange),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (onTapLink != null) {
                onTapLink!(url);
              }
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
