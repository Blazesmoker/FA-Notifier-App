import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:auto_size_text/auto_size_text.dart';
import '../model/shout.dart';
import 'openjournal.dart';
import 'openpost.dart';
import 'user_profile_screen.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ShoutWidget extends StatefulWidget {
  final Shout shout;
  final VoidCallback? onDelete;

  const ShoutWidget({Key? key, required this.shout, this.onDelete})
      : super(key: key);

  @override
  _ShoutWidgetState createState() => _ShoutWidgetState();
}

class _ShoutWidgetState extends State<ShoutWidget> {
  late bool showFullDate;

  late List<String> iconBeforeUrls;
  late List<String> iconAfterUrls;




  @override
  void initState() {
    super.initState();
    showFullDate = false;
  }


  Future<void> _handleFALink(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    final String urlToMatch = uri.toString();

    // 1. Gallery Folder Link:
    final RegExp galleryFolderRegex = RegExp(
        r'^https?://(?:www\.)?furaffinity\.net/gallery/([^/]+)/folder/(\d+)/([^/]+)/?$'
    );
    if (galleryFolderRegex.hasMatch(urlToMatch)) {
      final match = galleryFolderRegex.firstMatch(urlToMatch)!;
      final String tappedUsername = match.group(1)!;
      final String folderNumber = match.group(2)!;
      final String folderName = match.group(3)!;
      final String folderUrl =
          'https://www.furaffinity.net/gallery/$tappedUsername/folder/$folderNumber/$folderName/';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            nickname: tappedUsername,
            initialSection: ProfileSection.Gallery,
            initialFolderUrl: folderUrl,
            initialFolderName: folderName,
          ),
        ),
      );
      return;
    }

    // 2. User Link:
    final RegExp userRegex = RegExp(
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/user/([^/]+)/?$'
    );
    if (userRegex.hasMatch(urlToMatch)) {
      final String tappedUsername = userRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(nickname: tappedUsername),
        ),
      );
      return;
    }

    // 3. Journal Link:
    final RegExp journalRegex = RegExp(
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/journal/(\d+)/.*$'
    );
    if (journalRegex.hasMatch(urlToMatch)) {
      final String journalId = journalRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenJournal(uniqueNumber: journalId),
        ),
      );
      return;
    }

    // 4. Submission/View Link:
    final RegExp viewRegex = RegExp(
        r'^(?:https?://(?:www\.)?furaffinity\.net)?/view/(\d+)(?:/.*)?(?:#.*)?$'
    );
    if (viewRegex.hasMatch(urlToMatch)) {
      final String submissionId = viewRegex.firstMatch(urlToMatch)!.group(1)!;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OpenPost(uniqueNumber: submissionId, imageUrl: ''),
        ),
      );
      return;
    }

    // 5. Fallback: open externally.
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              if (widget.shout.profileNickname.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(
                      nickname: widget.shout.profileNickname,
                    ),
                  ),
                );
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15.0),
              child: Container(
                width: 100,
                height: 100,
                child: CachedNetworkImage(
                  imageUrl: widget.shout.avatarUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                  const Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) => Image.asset(
                    'assets/images/defaultpic.gif',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8.0),

          Expanded(
            child: Stack(
              children: [

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.shout.iconBeforeUrls.isNotEmpty)
                          ...widget.shout.iconBeforeUrls.map(
                                (url) => Image.network(url, width: 16, height: 16),
                          ),
                        Flexible(
                          child: AutoSizeText(
                            widget.shout.username,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            minFontSize: 16,
                          ),
                        ),
                        if (widget.shout.iconAfterUrls.isNotEmpty)
                          ...widget.shout.iconAfterUrls.map(
                                (url) => Image.network(url, width: 16, height: 16),
                          ),
                      ],
                    ),


                    // Row for the symbolized nickname.
                    Row(
                      children: [
                        Text(
                          widget.shout.symbol ?? "~",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFFE09321),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.shout.profileNickname,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFFE09321),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 0.0),
                    // Shout text rendered as HTML (with emoji support).
                    html_pkg.Html(
                      data: widget.shout.text,
                      style: {
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
                          color: Color(0xFFE09321),
                          textDecoration: TextDecoration.none,
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
                      },
                      onLinkTap: (url, _, __) =>
                          _handleFALink(context, url!),
                      extensions: [
                        // Tag extension to handle <i> tags and FA emoji images.
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
                                return Image.asset('assets/emojis/tongue.png',
                                    width: 20, height: 20);
                              case 'smilie evil':
                                return Image.asset('assets/emojis/evil.png',
                                    width: 20, height: 20);
                              case 'smilie lmao':
                                return Image.asset('assets/emojis/lmao.png',
                                    width: 20, height: 20);
                              case 'smilie gift':
                                return Image.asset('assets/emojis/gift.png',
                                    width: 20, height: 20);
                              case 'smilie derp':
                                return Image.asset('assets/emojis/derp.png',
                                    width: 20, height: 20);
                              case 'smilie teeth':
                                return Image.asset('assets/emojis/teeth.png',
                                    width: 20, height: 20);
                              case 'smilie cool':
                                return Image.asset('assets/emojis/cool.png',
                                    width: 20, height: 20);
                              case 'smilie huh':
                                return Image.asset('assets/emojis/huh.png',
                                    width: 20, height: 20);
                              case 'smilie cd':
                                return Image.asset('assets/emojis/cd.png',
                                    width: 20, height: 20);
                              case 'smilie coffee':
                                return Image.asset('assets/emojis/coffee.png',
                                    width: 20, height: 20);
                              case 'smilie sarcastic':
                                return Image.asset('assets/emojis/sarcastic.png',
                                    width: 20, height: 20);
                              case 'smilie veryhappy':
                                return Image.asset('assets/emojis/veryhappy.png',
                                    width: 20, height: 20);
                              case 'smilie wink':
                                return Image.asset('assets/emojis/wink.png',
                                    width: 20, height: 20);
                              case 'smilie whatever':
                                return Image.asset('assets/emojis/whatever.png',
                                    width: 20, height: 20);
                              case 'smilie crying':
                                return Image.asset('assets/emojis/crying.png',
                                    width: 20, height: 20);
                              case 'smilie love':
                                return Image.asset('assets/emojis/love.png',
                                    width: 20, height: 20);
                              case 'smilie serious':
                                return Image.asset('assets/emojis/serious.png',
                                    width: 20, height: 20);
                              case 'smilie yelling':
                                return Image.asset('assets/emojis/yelling.png',
                                    width: 20, height: 20);
                              case 'smilie oooh':
                                return Image.asset('assets/emojis/oooh.png',
                                    width: 20, height: 20);
                              case 'smilie angel':
                                return Image.asset('assets/emojis/angel.png',
                                    width: 20, height: 20);
                              case 'smilie dunno':
                                return Image.asset('assets/emojis/dunno.png',
                                    width: 20, height: 20);
                              case 'smilie nerd':
                                return Image.asset('assets/emojis/nerd.png',
                                    width: 20, height: 20);
                              case 'smilie sad':
                                return Image.asset('assets/emojis/sad.png',
                                    width: 20, height: 20);
                              case 'smilie zipped':
                                return Image.asset('assets/emojis/zipped.png',
                                    width: 20, height: 20);
                              case 'smilie smile':
                                return Image.asset('assets/emojis/smile.png',
                                    width: 20, height: 20);
                              case 'smilie badhairday':
                                return Image.asset('assets/emojis/badhairday.png',
                                    width: 20, height: 20);
                              case 'smilie embarrassed':
                                return Image.asset('assets/emojis/embarrassed.png',
                                    width: 20, height: 20);
                              case 'smilie note':
                                return Image.asset('assets/emojis/note.png',
                                    width: 20, height: 20);
                              case 'smilie sleepy':
                                return Image.asset('assets/emojis/sleepy.png',
                                    width: 20, height: 20);
                              default:
                                return const SizedBox.shrink();
                            }
                          },
                        ),
                        // Image extension for <img> tags.
            html_pkg.TagExtension(
              tagsToExtend: {"img"},
              builder: (html_pkg.ExtensionContext context) {
                final src = context.attributes['src'];
                if (src == null) return const SizedBox.shrink();
                final resolvedUrl = src.startsWith('//') ? 'https:$src' : src;
                return CachedNetworkImage(
                  imageUrl: resolvedUrl,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(),
                  ),
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                );
              },
            ),

            ],
                    ),

                    const SizedBox(height: 20.0),
                  ],
                ),
                // Date widget positioned at bottom right.
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        showFullDate = !showFullDate;
                      });
                    },
                    child: Text(
                      showFullDate
                          ? widget.shout.popupDateFull
                          : widget.shout.popupDateRelative,
                      style: const TextStyle(
                        fontSize: 12.0,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
