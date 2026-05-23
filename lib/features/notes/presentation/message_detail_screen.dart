import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:FANotifier/features/notes/data/note_message_service.dart';
import 'package:FANotifier/features/notes/data/notes_refresh_service.dart';
import 'package:FANotifier/main.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/notes/presentation/note_reply_screen.dart';
import 'package:FANotifier/shared/utils/fa_link_handler.dart';
import 'package:FANotifier/shared/utils/utils.dart';

class MessageDetailScreen extends StatefulWidget {
  final String messageLink;
  final String folder;

  const MessageDetailScreen({
    Key? key,
    required this.messageLink,
    required this.folder,
  }) : super(key: key);

  @override
  _MessageDetailScreenState createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
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
  String senderUsername = '';
  String senderLink = '';
  String recipientLink = '';
  String recipientUsername = '';
  int pageNumber = 1;
  bool isClassic = false;
  bool _shouldShowReplySuccess = false;
  bool _didTriggerRefreshOnExit = false;

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
        messageLink: widget.messageLink,
        folder: widget.folder,
      );

      if (result.redirected) {
        setState(() {
          errorMessage = 'Redirected. Possibly authentication issues.';
          isLoading = false;
        });
        return;
      }

      final details = result.details;
      if (details != null) {

        setState(() {
          isClassic = details.isClassic;
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
          recipientLink = details.recipientLink;
          recipientUsername = details.recipientUsername;
          isLoading = false;
        });
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


  Future<void> _markAsUnread() async {
    if (messageId == null) return;
    try {
      final statusCode = await _noteMessageService.markAsUnread(
        folder: widget.folder,
        messageId: messageId!,
        pageNumber: pageNumber,
      );

      if (statusCode == 302 || statusCode == 200) {
        showAppSnackBar(context, 'Message marked as unread');
        _triggerNotesRefreshOnce();
        Navigator.pop(context, 'marked_unread');
      } else {
        setState(() {
          errorMessage = 'Failed to mark as unread: $statusCode';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  GlobalKey _selectableKey = GlobalKey();

  void _triggerNotesRefreshOnce() {
    if (_didTriggerRefreshOnExit) return;
    _didTriggerRefreshOnExit = true;
    NotesRefreshService().triggerRefresh();
  }

  void _clearSelection() {
    setState(() {
      // Generates a new key to force the selectable widget to rebuild without a selection.
      _selectableKey = GlobalKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldShowReplySuccess) {
      _shouldShowReplySuccess = false; // Reset immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint('DEBUG: Showing snackbar from build cycle');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reply sent successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (TapUpDetails details) {
        final RenderBox? renderBox = _selectableKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          // Convert the global tap position to local coordinates of the selectable widget.
          final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
          // If the tap is outside the selectable widget’s bounds, clear the selection.
          if (!renderBox.size.contains(localPosition)) {
            _clearSelection();
          }
        } else {
          _clearSelection();
        }
      },
      child: PopScope(
        canPop: true,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop) return;
          _triggerNotesRefreshOnce();
        },
        child: SafeArea(
          top: false,
          child: Scaffold(
            appBar: AppBar(
              title: Text(subject),
              backgroundColor: Colors.black,
            ),
            backgroundColor: Colors.black,
            body: isLoading
                ? const Center(
              child: PulsatingLoadingIndicator(
                size: 108.0,
                assetPath: 'assets/icons/fathemed.png',
              ),
            )
                : errorMessage.isNotEmpty
                ? Center(
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            )
                : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!isClassic)
                        GestureDetector(
                          onTap: () {
                            final link = widget.folder == 'sent' ? recipientLink : senderLink;
                            if (link.isNotEmpty) {
                              handleFALink(context, link);
                            }
                          },
                          child: Container(
                            width: 60,
                            height: 60,
                            color: Colors.transparent,
                            child: Image.network(
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
                      Expanded(child:
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Sent by: ',
                                style: TextStyle(fontSize: 16, color: Colors.white),
                              ),
                              widget.folder == 'sent'
                                  ? Text(
                                      sender.isNotEmpty ? sender : 'Unknown sender',
                                      style: const TextStyle(fontSize: 16, color: Colors.white),
                                    )
                                  : InkWell(
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'To: ',
                                style: TextStyle(fontSize: 16, color: Colors.white),
                              ),
                              widget.folder == 'sent' && recipientLink.isNotEmpty
                                  ? InkWell(
                                      onTap: () => handleFALink(context, recipientLink),
                                      child: Text(
                                        recipient.isNotEmpty ? recipient : 'Unknown recipient',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFFE09321),
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      recipient.isNotEmpty ? recipient : 'Unknown recipient',
                                      style: const TextStyle(fontSize: 16, color: Colors.white),
                                    ),
                            ],
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
                  Expanded(
                    child: SingleChildScrollView(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          textSelectionTheme: TextSelectionThemeData(
                            selectionColor: Color(0xFFE09321).withOpacity(0.4),
                            selectionHandleColor: Color(0xFFE09321),
                          ),
                        ),
                        child: messageContentHtml.isNotEmpty
                            ? SelectionArea(
                                key: _selectableKey,
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
                                ),
                              )
                            : SelectableLinkify(
                                key: _selectableKey,
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
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.folder != 'sent')
                        OutlinedButton(
                          onPressed: _markAsUnread,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFE09321),
                            side: const BorderSide(
                              color: Color(0xFFE09321),
                            ),
                          ),
                          child: const Text('Mark Unread'),
                        ),
                      if (widget.folder != 'sent') const SizedBox(width: 8),


                      if (widget.folder != 'sent')
                        ElevatedButton(
                          onPressed: () {
                            final replyToUsername = widget.folder == 'sent'
                                ? recipientUsername
                                : senderUsername;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NoteReplyScreen(
                                  subject: subject,
                                  originalContent: messageContent,
                                  originalContentHtml: messageContentHtml.isNotEmpty ? messageContentHtml : null,
                                  username: replyToUsername.isNotEmpty ? replyToUsername : senderUsername,
                                  messageId: messageId ?? '',
                                  messageLink: widget.messageLink,
                                ),
                              ),
                            ).then((result) {
                              if (result == true) {
                                rootMessengerKey.currentState?.showSnackBar(
                                  const SnackBar(
                                    content: Text('Reply sent successfully!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE09321),
                          ),
                          child: const Text('Reply'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
