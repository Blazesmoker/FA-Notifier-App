import 'package:flutter/material.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:flutter_linkify/flutter_linkify.dart';

import 'package:FANotifier/features/notes/data/note_message_service.dart';
import 'package:FANotifier/shared/utils/fa_link_handler.dart';
import 'package:FANotifier/features/notes/domain/message_model.dart';

/// Dialog content for previewing a note/message.
class PreviewDialogContent extends StatefulWidget {
  final Message message;
  final String folder;
  final VoidCallback? onMarkedUnread;

  const PreviewDialogContent({
    Key? key,
    required this.message,
    required this.folder,
    this.onMarkedUnread,
  }) : super(key: key);

  @override
  _PreviewDialogContentState createState() => _PreviewDialogContentState();
}

class _PreviewDialogContentState extends State<PreviewDialogContent> {
  late final NoteMessageService _noteMessageService =
      NoteMessageService();

  bool isLoading = true;
  String errorMessage = '';
  String subject = '';
  String sender = '';
  String recipient = '';
  String sentDate = '';
  String avatarUrl = '';
  String messageContent = '';
  String messageContentHtml = '';
  String? messageId;
  String senderLink = '';
  String senderUsername = '';
  int pageNumber = 1;
  bool _isClassic = false;

  @override
  void initState() {
    super.initState();
    _fetchMessageDetails();
  }

  @override
  void dispose() {
    _noteMessageService.close();
    super.dispose();
  }

  Future<void> _fetchMessageDetails() async {
    try {
      final result = await _noteMessageService.fetchMessageDetails(
        messageLink: widget.message.link,
        folder: widget.folder,
        closeConnection: true,
      );

      final details = result.details;
      if (details != null) {

        setState(() {
          _isClassic = details.isClassic;
          messageId = details.messageId;
          pageNumber = details.pageNumber;
          subject = details.subject;
          sender = details.sender;
          recipient = details.recipient;
          sentDate = details.sentDate;
          avatarUrl = details.avatarUrl;
          messageContent = details.messageContent;
          messageContentHtml = details.messageContentHtml;
          senderLink = details.senderLink;
          senderUsername = details.senderUsername;
          isLoading = false;
        });

        if (widget.onMarkedUnread != null) {
          widget.onMarkedUnread!();
        }
      } else {
        setState(() {
          errorMessage = 'Failed to fetch message: ${result.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE09321),),
            ),
            SizedBox(width: 12),
            Text(
              'Loading...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          errorMessage,
          style: const TextStyle(color: Colors.red, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }

    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!_isClassic)
                    GestureDetector(
                      onTap: () {
                        if (senderLink.isNotEmpty) {
                          handleFALink(context, senderLink);
                        }
                      },
                      child: Container(
                        width: 60,
                        height: 60,
                        color: Colors.transparent,
                        child: FaNetworkImage(
                          'https:$avatarUrl',
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          errorBuilder: (context, error, stackTrace) {
                            return Transform.scale(
                              scale: 1.05,
                              child: Image.asset(
                                'assets/images/defaultpic.gif',
                                fit: BoxFit.cover,
                              ),
                            );
                          },
                        ),

                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Sent by: ',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                            InkWell(
                              onTap: senderLink.isNotEmpty
                                  ? () => handleFALink(context, senderLink)
                                  : null,
                              child: Text(
                                sender.isNotEmpty ? sender : 'Unknown sender',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFE09321),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'To: $recipient',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),

                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Date: $sentDate',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const Divider(height: 20, thickness: 1, color: Colors.white54),
              if (messageContentHtml.isNotEmpty)
                Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      selectionColor: const Color(0xFFE09321).withValues(alpha: 0.4),
                      selectionHandleColor: const Color(0xFFE09321),
                    ),
                  ),
                  child: SelectionArea(
                    child: html_pkg.Html(
                      data: messageContentHtml,
                      style: {
                        'body': html_pkg.Style(
                          margin: html_pkg.Margins.zero,
                          padding: html_pkg.HtmlPaddings.zero,
                          color: Colors.white,
                          fontSize: html_pkg.FontSize(16),
                        ),
                        'b': html_pkg.Style(fontWeight: FontWeight.bold),
                        'strong': html_pkg.Style(fontWeight: FontWeight.bold),
                        'i': html_pkg.Style(fontStyle: FontStyle.italic),
                        '.bbcode_i': html_pkg.Style(fontStyle: FontStyle.italic),
                        'u': html_pkg.Style(textDecoration: TextDecoration.underline),
                        '.bbcode_u': html_pkg.Style(textDecoration: TextDecoration.underline),
                        '.bbcode_center': html_pkg.Style(
                          display: html_pkg.Display.block,
                          textAlign: TextAlign.center,
                        ),
                        '.bbcode_left': html_pkg.Style(
                          display: html_pkg.Display.block,
                          textAlign: TextAlign.left,
                        ),
                        '.bbcode_right': html_pkg.Style(
                          display: html_pkg.Display.block,
                          textAlign: TextAlign.right,
                        ),
                        'a': html_pkg.Style(
                          color: const Color(0xFFE09321),
                          textDecoration: TextDecoration.none,
                        ),
                      },
                      onLinkTap: (url, _, __) {
                        if (url != null) handleFALink(context, url);
                      },
                      extensions: [faHtmlImageExtension()],
                    ),
                  ),
                )
              else
                SelectableLinkify(
                  onOpen: (link) async {
                    await handleFALink(context, link.url);
                  },
                  text: messageContent,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                  linkStyle: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFFE09321),
                    decoration: TextDecoration.none,
                    decorationColor: Color(0xFFE09321),
                  ),
                  selectionControls: MaterialTextSelectionControls(),
                ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.folder != 'sent') const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE09321),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
