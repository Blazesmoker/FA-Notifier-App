import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;

Map<String, html_pkg.Style> userProfileHtmlStyles() {
  return {
    "body": html_pkg.Style(
      textAlign: TextAlign.left,
      fontSize: html_pkg.FontSize(16),
      color: Colors.white,
    ),
    "p": html_pkg.Style(
      fontSize: html_pkg.FontSize(16),
      color: Colors.white,
    ),
    "a": html_pkg.Style(
      color: const Color(0xFFE09321),
    ),
    "img": html_pkg.Style(
      width: html_pkg.Width(50.0),
      height: html_pkg.Height(50.0),
    ),
    "strong": html_pkg.Style(
      color: Colors.black,
      fontWeight: FontWeight.bold,
    ),
    "u": html_pkg.Style(
      color: Colors.black,
    ),
    ".bbcode_right": html_pkg.Style(
      textAlign: TextAlign.right,
    ),
    ".bbcode_right .bbcode_sup, .bbcode_right sup": html_pkg.Style(
      textAlign: TextAlign.right,
    ),
    ".bbcode_center": html_pkg.Style(
      textAlign: TextAlign.center,
    ),
    ".bbcode_left": html_pkg.Style(
      textAlign: TextAlign.left,
    ),
    "hr": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.symmetric(vertical: 8),
      margin: html_pkg.Margins.symmetric(vertical: 8),
      height: html_pkg.Height(1),
    ),
  };
}

Map<String, html_pkg.Style> userProfileHtmlStylesCompact() {
  return {
    "body": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      textAlign: TextAlign.left,
      fontSize: html_pkg.FontSize(16),
      color: Colors.white,
    ),
    "p": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      fontSize: html_pkg.FontSize(16),
      color: Colors.white,
    ),
    "a": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      color: const Color(0xFFE09321),
      textDecoration: TextDecoration.none,
    ),
    "img": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      width: html_pkg.Width(50.0),
      height: html_pkg.Height(50.0),
    ),
    "strong": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.symmetric(vertical: 8),
      margin: html_pkg.Margins.symmetric(vertical: 4),
      color: Colors.white,
      fontWeight: FontWeight.bold,
    ),
    "u": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      color: Colors.white,
    ),
    ".bbcode_right": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      textAlign: TextAlign.right,
    ),
    ".bbcode_right .bbcode_sup, .bbcode_right sup": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      textAlign: TextAlign.right,
    ),
    ".bbcode_center": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      textAlign: TextAlign.center,
    ),
    "hr": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.symmetric(vertical: 8),
      margin: html_pkg.Margins.symmetric(vertical: 8),
      height: html_pkg.Height(1),
    ),
    ".bbcode_left": html_pkg.Style(
      padding: html_pkg.HtmlPaddings.zero,
      margin: html_pkg.Margins.zero,
      textAlign: TextAlign.left,
    ),
  };
}

List<html_pkg.HtmlExtension> buildUserProfileBBCodeExtensions() {
  return [
    html_pkg.TagExtension(
      tagsToExtend: {"i"},
      builder: (html_pkg.ExtensionContext context) {
        final classAttr = context.attributes['class'];

        if (classAttr == 'bbcode bbcode_i') {
          return Text(
            context.styledElement?.element?.text ?? "",
            style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white),
          );
        }

        switch (classAttr) {
          case 'smilie tongue':
            return Image.asset('assets/emojis/tongue.png', width: 20, height: 20);
          case 'smilie evil':
            return Image.asset('assets/emojis/evil.png', width: 20, height: 20);
          case 'smilie lmao':
            return Image.asset('assets/emojis/lmao.png', width: 20, height: 20);
          case 'smilie gift':
            return Image.asset('assets/emojis/gift.png', width: 20, height: 20);
          case 'smilie derp':
            return Image.asset('assets/emojis/derp.png', width: 20, height: 20);
          case 'smilie teeth':
            return Image.asset('assets/emojis/teeth.png', width: 20, height: 20);
          case 'smilie cool':
            return Image.asset('assets/emojis/cool.png', width: 20, height: 20);
          case 'smilie huh':
            return Image.asset('assets/emojis/huh.png', width: 20, height: 20);
          case 'smilie cd':
            return Image.asset('assets/emojis/cd.png', width: 20, height: 20);
          case 'smilie coffee':
            return Image.asset('assets/emojis/coffee.png', width: 20, height: 20);
          case 'smilie sarcastic':
            return Image.asset('assets/emojis/sarcastic.png', width: 20, height: 20);
          case 'smilie veryhappy':
            return Image.asset('assets/emojis/veryhappy.png', width: 20, height: 20);
          case 'smilie wink':
            return Image.asset('assets/emojis/wink.png', width: 20, height: 20);
          case 'smilie whatever':
            return Image.asset('assets/emojis/whatever.png', width: 20, height: 20);
          case 'smilie crying':
            return Image.asset('assets/emojis/crying.png', width: 20, height: 20);
          case 'smilie love':
            return Image.asset('assets/emojis/love.png', width: 20, height: 20);
          case 'smilie serious':
            return Image.asset('assets/emojis/serious.png', width: 20, height: 20);
          case 'smilie yelling':
            return Image.asset('assets/emojis/yelling.png', width: 20, height: 20);
          case 'smilie oooh':
            return Image.asset('assets/emojis/oooh.png', width: 20, height: 20);
          case 'smilie angel':
            return Image.asset('assets/emojis/angel.png', width: 20, height: 20);
          case 'smilie dunno':
            return Image.asset('assets/emojis/dunno.png', width: 20, height: 20);
          case 'smilie nerd':
            return Image.asset('assets/emojis/nerd.png', width: 20, height: 20);
          case 'smilie sad':
            return Image.asset('assets/emojis/sad.png', width: 20, height: 20);
          case 'smilie zipped':
            return Image.asset('assets/emojis/zipped.png', width: 20, height: 20);
          case 'smilie smile':
            return Image.asset('assets/emojis/smile.png', width: 20, height: 20);
          case 'smilie badhairday':
            return Image.asset('assets/emojis/badhairday.png', width: 20, height: 20);
          case 'smilie embarrassed':
            return Image.asset('assets/emojis/embarrassed.png', width: 20, height: 20);
          case 'smilie note':
            return Image.asset('assets/emojis/note.png', width: 20, height: 20);
          case 'smilie sleepy':
            return Image.asset('assets/emojis/sleepy.png', width: 20, height: 20);
          default:
            return const SizedBox.shrink();
        }
      },
    ),
    html_pkg.TagExtension(
      tagsToExtend: {"img"},
      builder: (html_pkg.ExtensionContext context) {
        final src = context.attributes['src'];
        if (src == null) {
          return const SizedBox.shrink();
        }

        final resolvedUrl = src.startsWith('//') ? 'https:$src' : src;

        return Image.network(
          resolvedUrl,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return const SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              'assets/images/defaultpic.gif',
              width: 50,
              height: 50,
              fit: BoxFit.cover,
            );
          },
        );

      },
    ),
  ];
}


