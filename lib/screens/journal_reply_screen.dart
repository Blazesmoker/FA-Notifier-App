import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../services/fa_http.dart';

class JournalReplyScreen extends StatefulWidget {
  final String submissionId; // Journal ID
  final String commentId; // Comment ID being replied to
  final String username;
  final String profileImage;
  final String commentText;
  final Function(String) onSendReply;

  const JournalReplyScreen({
    required this.submissionId,
    required this.commentId,
    required this.username,
    required this.profileImage,
    required this.commentText,
    required this.onSendReply,
    Key? key,
  }) : super(key: key);

  @override
  _JournalReplyScreenState createState() => _JournalReplyScreenState();
}

class _JournalReplyScreenState extends State<JournalReplyScreen> {
  final TextEditingController _replyController = TextEditingController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock),
  );
  bool _isSending = false;

  Future<void> _sendReply() async {
    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reply cannot be empty.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final success = await _submitJournalReply(
        message: replyText,
        submissionId: widget.submissionId,
        commentId: widget.commentId,
      );

      if (success) {
        widget.onSendReply(replyText);
        _replyController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply posted successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to post reply. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<bool> _submitJournalReply({
    required String message,
    required String submissionId,
    required String commentId,
  }) async {
    String sanitizedCommentId = commentId;
    if (sanitizedCommentId.startsWith('#cid:')) {
      sanitizedCommentId = sanitizedCommentId.substring(5);
    } else if (sanitizedCommentId.startsWith('cid:')) {
      sanitizedCommentId = sanitizedCommentId.substring(4);
    }
    sanitizedCommentId = sanitizedCommentId.trim();
    if (!RegExp(r'^\d+$').hasMatch(sanitizedCommentId)) {
      throw Exception('Invalid comment ID.');
    }

    final cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    final cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('Not authenticated.');
    }

    final postUrl = 'https://www.furaffinity.net/journal/$submissionId/';
    final body = {
      'action': 'replyto',
      'replyto': sanitizedCommentId,
      'reply': message,
      'submit': 'Post Comment',
    };

    final resp = await http.post(
      Uri.parse(postUrl),
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB',
        'User-Agent': FAHttp.userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': '$postUrl#cid:$sanitizedCommentId',
      },
      body: body,
    );

    if (resp.statusCode == 302) return true;
    if (resp.statusCode == 200 && resp.body.contains('Your comment has been posted')) {
      return true;
    }
    if (resp.statusCode == 200) {
      final doc = html_parser.parse(resp.body);
      final err = doc.querySelector('.error_message_class')?.text ?? 'Unknown error';
      throw Exception(err);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _isSending ? null : () => Navigator.pop(context),
          ),
          title: const Text("Reply to Comment"),
          actions: [
            IconButton(
              icon: _isSending
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Icon(Icons.send),
              onPressed: _isSending ? null : _sendReply,
            ),
          ],
        ),
        body: SafeArea(
          bottom: true,
          maintainBottomViewPadding: true,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            physics: const ClampingScrollPhysics(),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        widget.profileImage,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) {
                            return child;
                          }
                          return Container(
                            width: 36,
                            height: 36,
                            color: Colors.grey,
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 36,
                            height: 36,
                            color: Colors.grey,
                            child: const Icon(
                              Icons.person,
                              size: 24,
                            ),
                          );
                        },
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
                GestureDetector(
                  onLongPress: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(widget.username),
                      content: SelectableText(widget.commentText),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      widget.commentText,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.grey),
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(minHeight: 100),
                  child: TextField(
                    controller: _replyController,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    maxLines: null,
                    enableInteractiveSelection: true,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Write your reply...',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(8),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}