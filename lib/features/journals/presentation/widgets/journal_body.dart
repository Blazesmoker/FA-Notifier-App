import 'package:material_ui/material_ui.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

Widget buildJournalBody({
  required String? submissionDescription,
  required void Function(String?) onLinkTap,
}) {
  return html_pkg.Html(
    data: submissionDescription ?? '',
    style: {
      "body": html_pkg.Style(
        textAlign: TextAlign.left,
        fontSize: html_pkg.FontSize(16),
        padding: html_pkg.HtmlPaddings.zero,
        margin: html_pkg.Margins.zero,
        backgroundColor: Colors.transparent,
      ),
      "a": html_pkg.Style(
        textDecoration: TextDecoration.none,
        color: const Color(0xFFE09321),
      ),
      "hr": html_pkg.Style(
        padding: html_pkg.HtmlPaddings.symmetric(vertical: 8),
        margin: html_pkg.Margins.symmetric(vertical: 8),
        height: html_pkg.Height(1),
      ),
      ".bbcode_center": html_pkg.Style(
        textAlign: TextAlign.center,
        display: html_pkg.Display.block,
      ),
      ".bbcode_right": html_pkg.Style(
        textAlign: TextAlign.right,
        display: html_pkg.Display.block,
      ),
      ".bbcode_left": html_pkg.Style(
        textAlign: TextAlign.left,
        display: html_pkg.Display.block,
      ),
    },
    onLinkTap: (url, _, _) => onLinkTap(url),
    extensions: [
      html_pkg.TagExtension(
        tagsToExtend: {"i"},
        builder: (html_pkg.ExtensionContext context) {
          final classAttr = context.attributes['class'];
          if (classAttr == 'bbcode bbcode_i') {
            return Text(
              context.styledElement?.element?.text ?? "",
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.white,
              ),
            );
          }
          switch (classAttr) {
            case 'smilie tongue':
              return Image.asset(
                'assets/emojis/tongue.png',
                width: 20,
                height: 20,
              );
            case 'smilie evil':
              return Image.asset(
                'assets/emojis/evil.png',
                width: 20,
                height: 20,
              );
            case 'smilie lmao':
              return Image.asset(
                'assets/emojis/lmao.png',
                width: 20,
                height: 20,
              );
            case 'smilie gift':
              return Image.asset(
                'assets/emojis/gift.png',
                width: 20,
                height: 20,
              );
            case 'smilie derp':
              return Image.asset(
                'assets/emojis/derp.png',
                width: 20,
                height: 20,
              );
            case 'smilie teeth':
              return Image.asset(
                'assets/emojis/teeth.png',
                width: 20,
                height: 20,
              );
            case 'smilie cool':
              return Image.asset(
                'assets/emojis/cool.png',
                width: 20,
                height: 20,
              );
            case 'smilie huh':
              return Image.asset(
                'assets/emojis/huh.png',
                width: 20,
                height: 20,
              );
            case 'smilie cd':
              return Image.asset('assets/emojis/cd.png', width: 20, height: 20);
            case 'smilie coffee':
              return Image.asset(
                'assets/emojis/coffee.png',
                width: 20,
                height: 20,
              );
            case 'smilie sarcastic':
              return Image.asset(
                'assets/emojis/sarcastic.png',
                width: 20,
                height: 20,
              );
            case 'smilie veryhappy':
              return Image.asset(
                'assets/emojis/veryhappy.png',
                width: 20,
                height: 20,
              );
            case 'smilie wink':
              return Image.asset(
                'assets/emojis/wink.png',
                width: 20,
                height: 20,
              );
            case 'smilie whatever':
              return Image.asset(
                'assets/emojis/whatever.png',
                width: 20,
                height: 20,
              );
            case 'smilie crying':
              return Image.asset(
                'assets/emojis/crying.png',
                width: 20,
                height: 20,
              );
            case 'smilie love':
              return Image.asset(
                'assets/emojis/love.png',
                width: 20,
                height: 20,
              );
            case 'smilie serious':
              return Image.asset(
                'assets/emojis/serious.png',
                width: 20,
                height: 20,
              );
            case 'smilie yelling':
              return Image.asset(
                'assets/emojis/yelling.png',
                width: 20,
                height: 20,
              );
            case 'smilie oooh':
              return Image.asset(
                'assets/emojis/oooh.png',
                width: 20,
                height: 20,
              );
            case 'smilie angel':
              return Image.asset(
                'assets/emojis/angel.png',
                width: 20,
                height: 20,
              );
            case 'smilie dunno':
              return Image.asset(
                'assets/emojis/dunno.png',
                width: 20,
                height: 20,
              );
            case 'smilie nerd':
              return Image.asset(
                'assets/emojis/nerd.png',
                width: 20,
                height: 20,
              );
            case 'smilie sad':
              return Image.asset(
                'assets/emojis/sad.png',
                width: 20,
                height: 20,
              );
            case 'smilie zipped':
              return Image.asset(
                'assets/emojis/zipped.png',
                width: 20,
                height: 20,
              );
            case 'smilie smile':
              return Image.asset(
                'assets/emojis/smile.png',
                width: 20,
                height: 20,
              );
            case 'smilie badhairday':
              return Image.asset(
                'assets/emojis/badhairday.png',
                width: 20,
                height: 20,
              );
            case 'smilie embarrassed':
              return Image.asset(
                'assets/emojis/embarrassed.png',
                width: 20,
                height: 20,
              );
            case 'smilie note':
              return Image.asset(
                'assets/emojis/note.png',
                width: 20,
                height: 20,
              );
            case 'smilie sleepy':
              return Image.asset(
                'assets/emojis/sleepy.png',
                width: 20,
                height: 20,
              );
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
          // Check if this image is a profile emoji.
          if (resolvedUrl.contains("a.furaffinity.net") &&
              resolvedUrl.endsWith(".gif")) {
            return FaNetworkImage(
              resolvedUrl,
              width: 50,
              // profile emoji size.
              height: 50,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return const SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Image.asset(
                  'assets/images/defaultpic.gif',
                  width: 50,
                  height: 50,
                  fit: BoxFit.contain,
                );
              },
            );
          }

          return FaNetworkImage(
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
    ],
  );
}
