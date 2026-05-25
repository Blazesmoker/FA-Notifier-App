import 'package:flutter/material.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter_html/flutter_html.dart' as html;

import 'package:FANotifier/features/journals/data/journal_comment_service.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';

class JournalReplyScreen extends StatefulWidget {
  final String submissionId; // Journal ID
  final String commentId; // Comment ID being replied to
  final String username;
  final String profileImage;

  /// Plain text fallback (for copy / safety)
  final String? commentText;

  /// Parsed HTML of the comment (preferred)
  final String? commentHtml;

  final Function(String) onSendReply;

  const JournalReplyScreen({
    required this.submissionId,
    required this.commentId,
    required this.username,
    required this.profileImage,
    required this.onSendReply,
    this.commentText,
    this.commentHtml,
    Key? key,
  }) : super(key: key);

  @override
  _JournalReplyScreenState createState() => _JournalReplyScreenState();
}

class _JournalReplyScreenState extends State<JournalReplyScreen> {
  final TextEditingController _replyController = TextEditingController();
  final JournalCommentService _commentService = JournalCommentService();

  bool _isSending = false;

  bool get _hasHtml =>
      widget.commentHtml != null && widget.commentHtml!.trim().isNotEmpty;



  Future<void> _sendReply() async {
    final replyText = _replyController.text.trim();

    if (replyText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reply cannot be empty.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final success = await _commentService.submitReplyToComment(
        message: replyText,
        journalId: widget.submissionId,
        commentId: widget.commentId,
      );

      if (success) {
        widget.onSendReply(replyText);
        _replyController.clear();
        Navigator.pop(context, true);
      } else {
        _showError('Failed to post reply.');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _onRequestClose() async {
    final confirmed = await ConfirmCloseDialog.show(context);
    if (confirmed && mounted) Navigator.pop(context);
  }



  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) _onRequestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onRequestClose,
          ),
          title: const Text('Reply to Comment'),
          actions: [
            IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: _isSending ? null : _sendReply,
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

              Row(
                children: [
                  FaNetworkImage(
                    widget.profileImage,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }
                      return Image.asset(
                        'assets/images/defaultpic.gif',
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      );
                    },
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/defaultpic.gif',
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.username,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),


              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _hasHtml
                    ? html.Html(
                  data: widget.commentHtml!,
                  style: {
                    "body": html.Style(
                      margin: html.Margins.zero,
                      padding: html.HtmlPaddings.zero,
                      color: Colors.grey.shade300,
                      fontSize: html.FontSize(14),
                    ),


                    "i": html.Style(fontStyle: FontStyle.italic),
                    ".bbcode_i": html.Style(fontStyle: FontStyle.italic),
                    "span.bbcode_i": html.Style(fontStyle: FontStyle.italic),


                    "b": html.Style(fontWeight: FontWeight.bold),
                    "strong": html.Style(fontWeight: FontWeight.bold),


                    "u": html.Style(textDecoration: TextDecoration.underline),
                    ".bbcode_u": html.Style(textDecoration: TextDecoration.underline),


                    ".bbcode_center": html.Style(
                      display: html.Display.block,
                      textAlign: TextAlign.center,
                    ),
                    ".bbcode_left": html.Style(
                      display: html.Display.block,
                      textAlign: TextAlign.left,
                    ),
                    ".bbcode_right": html.Style(
                      display: html.Display.block,
                      textAlign: TextAlign.right,
                    ),


                    "a": html.Style(
                      color: const Color(0xFFE09321),
                      textDecoration: TextDecoration.none,
                    ),
                  },
                  extensions: [faHtmlImageExtension()],
                )

                    : Text(
                  widget.commentText ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),

              const Divider(),
              const SizedBox(height: 8),


              TextField(
                controller: _replyController,
                maxLines: null,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Write your reply...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(8),
                ),
                contextMenuBuilder:
                BBCodeContextMenu.builder(_replyController),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
