import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_html/flutter_html.dart' as html;

import '../services/fa_cookie_helper.dart';
import '../services/fa_http.dart';
import '../utils/bbcode_context_menu.dart';
import '../widgets/confirm_close_dialog.dart';

class ReplyScreen extends StatefulWidget {
  final Map<String, dynamic> comment;
  final Function(String) onSendReply;
  final String uniqueNumber;
  final bool isClassic;

  const ReplyScreen({
    required this.comment,
    required this.onSendReply,
    required this.uniqueNumber,
    required this.isClassic,
    Key? key,
  }) : super(key: key);

  @override
  _ReplyScreenState createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  String? extractClassicCommentId(String input) {
    final regex = RegExp(r'/replyto/submission/(\d+)/');
    final match = regex.firstMatch(input);
    return match != null ? match.group(1) : input;
  }

  void _sendReply() async {
    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) return;

    setState(() => _isSending = true);

    String? replyId;
    if (widget.isClassic) {
      replyId = extractClassicCommentId(widget.comment['replyLink'] ?? '');
    } else {
      replyId = widget.comment['commentId'];
    }

    try {
      final success = await submitCommentOrReply(
        message: replyText,
        commentId: replyId,
        submissionId: widget.uniqueNumber,
        isClassic: widget.isClassic,
      );

      if (success) {
        widget.onSendReply(replyText);
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply posted!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        _showError('Error posting reply.');
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

  Future<bool> submitCommentOrReply({
    required String message,
    String? submissionId,
    String? commentId,
    required bool isClassic,
  }) async {
    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) return false;

    String postUrl;
    Map<String, String> body;

    if (isClassic) {
      postUrl = 'https://www.furaffinity.net/view/$submissionId/';
      body = {
        'action': 'replyto',
        'replyto': commentId ?? '',
        'reply': message,
        'submit': 'Post Comment',
      };
    } else {
      postUrl = 'https://www.furaffinity.net/replyto/submission/$commentId/';
      body = {
        'reply': message,
        'send': 'Submit Comment',
        'comment': commentId ?? '',
        'name': '',
      };
    }

    final response = await http.post(
      Uri.parse(postUrl),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB',
        ),
        'User-Agent': FAHttp.userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );

    return response.statusCode == 302 ||
        response.body.contains('Your comment has been posted');
  }

  @override
  Widget build(BuildContext context) {
    final String? htmlComment = widget.comment['html'];
    final String plainText = widget.comment['text'] ?? '';

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
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// HEADER
                Row(
                  children: [
                    Image.network(
                      widget.comment['profileImage'] ?? '',
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
                      widget.comment['username'] ?? 'Anonymous',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                /// COMMENT PREVIEW (HTML)
                GestureDetector(
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(widget.comment['username'] ?? 'Anonymous'),
                        content: SingleChildScrollView(
                          child: html.Html(data: htmlComment ?? plainText),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: htmlComment != null && htmlComment.trim().isNotEmpty
                        ? html.Html(
                      data: htmlComment,
                      style: {
                        "body": html.Style(
                          margin: html.Margins.zero,
                          padding: html.HtmlPaddings.zero,
                          color: Colors.grey.shade300,
                          fontSize: html.FontSize(14),
                        ),
                        "b": html.Style(fontWeight: FontWeight.bold),
                        "i": html.Style(fontStyle: FontStyle.italic),
                        "u": html.Style(
                            textDecoration: TextDecoration.underline),
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
                    )
                        : Text(
                      plainText,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),

                const Divider(),
                const SizedBox(height: 12),

                /// REPLY INPUT
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
