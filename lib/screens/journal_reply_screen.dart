import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class JournalReplyScreen extends StatefulWidget {
  final String submissionId; // Submission (Journal) ID
  final String commentId; // Comment ID being replied to
  final Function(String) onSendReply;

  final String username;
  final String profileImage;
  final String commentText;

  const JournalReplyScreen({
    required this.submissionId,
    required this.commentId,
    required this.onSendReply,
    required this.username,
    required this.profileImage,
    required this.commentText,
    Key? key,
  }) : super(key: key);

  @override
  _JournalReplyScreenState createState() => _JournalReplyScreenState();
}

class _JournalReplyScreenState extends State<JournalReplyScreen> {
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  void _sendReply() async {
    print("_sendReply method called");
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

    setState(() {
      _isSending = true;
    });

    print("Reply Text: $replyText");
    print("Submission ID: ${widget.submissionId}");
    print("Comment ID: ${widget.commentId}");

    try {
      bool success = await submitJournalReply(
        message: replyText,
        submissionId: widget.submissionId,
        commentId: widget.commentId,
      );

      if (success) {
        // Notifies the parent widget about the successful reply
        widget.onSendReply(replyText);

        // Clears the text field
        _replyController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply posted successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Navigate back after a short delay to allow the SnackBar to display
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
      print("Error in _sendReply: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }


  Future<bool> submitJournalReply({
    required String message,
    required String submissionId,
    required String commentId,
  }) async {

    print('[DEBUG] Original commentId: "$commentId"');

    // Removes "#cid:" or "cid:" if they appear at the start.
    String sanitizedCommentId = commentId;
    if (sanitizedCommentId.startsWith('#cid:')) {
      // If it starts with "#cid:", remove the first 5 characters.
      sanitizedCommentId = sanitizedCommentId.substring(5);
    } else if (sanitizedCommentId.startsWith('cid:')) {
      // If it starts with "cid:", remove the first 4 characters.
      sanitizedCommentId = sanitizedCommentId.substring(4);
    }

    // Trim whitespace and verify it’s all digits.
    sanitizedCommentId = sanitizedCommentId.trim();
    print('[DEBUG] After removing "#cid:" or "cid:" prefix: "$sanitizedCommentId"');

    if (!RegExp(r'^\d+$').hasMatch(sanitizedCommentId)) {
      throw Exception('Invalid comment ID. (Not purely digits)');
    }

    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      throw Exception('Authentication cookies not found. Please log in again.');
    }

    final postUrl = 'https://www.furaffinity.net/journal/$submissionId/';
    final body = {
      'action': 'replyto',
      'replyto': sanitizedCommentId,
      'reply': message,
      'submit': 'Post Comment',
    };

    print('[DEBUG] POST URL: $postUrl');
    print('[DEBUG] POST body: $body');

    final response = await http.post(
      Uri.parse(postUrl),
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': 'https://www.furaffinity.net/journal/$submissionId/#cid:$sanitizedCommentId',
      },
      body: body,
    );

    print('[DEBUG] Status Code: ${response.statusCode}');
    print('[DEBUG] Response Body: ${response.body}');

    if (response.statusCode == 302) {
      return true;
    } else if (response.statusCode == 200) {
      if (response.body.contains('Your comment has been posted')) {
        return true;
      } else {
        final document = html_parser.parse(response.body);
        final errorElement = document.querySelector('.error_message_class');
        final errorMessage =
        errorElement != null ? errorElement.text : 'Unknown error occurred.';
        throw Exception('Failed to post reply: $errorMessage');
      }
    } else {
      throw Exception('Unexpected status code: ${response.statusCode}');
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Reply to Comment"),
        actions: [
          IconButton(
            icon: _isSending
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2.0,
              ),
            )
                : const Icon(Icons.send),
            onPressed: _isSending ? null : _sendReply,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: CachedNetworkImage(
                      imageUrl: widget.profileImage,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      errorWidget: (context, url, error) => Image.asset(
                        'assets/images/defaultpic.gif',
                        fit: BoxFit.cover,
                      ),
                    ),
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
            Text(
              widget.commentText,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _replyController,
                style: const TextStyle(color: Colors.white),
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  hintText: 'Write your reply...',
                  hintStyle: TextStyle(color: Colors.white70),
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.newline,
              ),
            ),

          ],
        ),
      ),
    );
  }

}
