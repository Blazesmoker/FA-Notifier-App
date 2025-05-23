import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

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
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Extract numeric ID from a classic reply link (e.g. "/replyto/submission/184823275/")
  String? extractClassicCommentId(String input) {
    final regex = RegExp(r'/replyto/submission/(\d+)/');
    final match = regex.firstMatch(input);
    return match != null ? match.group(1) : input; // fallback if already numeric
  }

  void _sendReply() async {
    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    // In classic mode, use the "replyLink" from the comment object.
    // Make sure your comment map includes "replyLink" from the <td class="reply-link">.
    String? replyId;
    if (widget.isClassic) {
      replyId = extractClassicCommentId(widget.comment['replyLink'] ?? '');
    } else {
      replyId = widget.comment['commentId'];
    }

    // Debug prints
    print("Final sending parameters:");
    print("Mode: ${widget.isClassic ? 'Classic' : 'Modern'}");
    print("Submission ID: ${widget.uniqueNumber}");
    print("Reply ID (to be sent as 'replyto'): $replyId");
    print("Message: $replyText");

    try {
      bool success = await submitCommentOrReply(
        message: replyText,
        commentId: replyId,
        submissionId: widget.uniqueNumber,
        isClassic: widget.isClassic,
      );

      if (success) {
        widget.onSendReply(replyText);
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Reply posted!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
            const Text('Error posting reply. Please try again.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
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
    }

    setState(() {
      _isSending = false;
    });
  }

  Future<bool> submitCommentOrReply({
    required String message,
    String? submissionId,
    String? commentId,
    required bool isClassic,
  }) async {

    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) return false;


    String postUrl;
    Map<String, String> body;

    if (isClassic) {

      if (submissionId == null) return false;
      postUrl = 'https://www.furaffinity.net/view/$submissionId/';
      if (commentId != null && commentId.isNotEmpty) {
        body = {
          'action': 'replyto',
          'replyto': commentId,
          'reply': message,
          'submit': 'Post Comment',
        };
      } else {

        body = {
          'action': 'reply',
          'f': '0',
          'reply': message,
          'mysubmit': 'Add Reply',
        };
      }
    } else {
      // Modern (beta) style
      if (commentId != null && commentId.isNotEmpty) {
        postUrl = 'https://www.furaffinity.net/replyto/submission/$commentId/';
        body = {
          'reply': message,
          'send': 'Submit Comment',
          'comment': commentId,
          'name': '',
        };
      } else if (submissionId != null) {
        postUrl = 'https://www.furaffinity.net/view/$submissionId/';
        body = {
          'reply': message,
          'f': '0',
          'action': 'reply',
        };
      } else {
        return false;
      }
    }

    // Debug prints
    print("Sending POST request:");
    print("POST URL: $postUrl");
    print("Request Body: $body");


    Map<String, String> headers = {
      'Cookie': 'a=$cookieA; b=$cookieB',
      'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
      'Content-Type': 'application/x-www-form-urlencoded',
    };

    if (isClassic && commentId != null && commentId.isNotEmpty) {
      headers['Referer'] =
      'https://www.furaffinity.net/journal/$submissionId/#cid:$commentId';
    }

    final response = await http.post(
      Uri.parse(postUrl),
      headers: headers,
      body: body,
    );

    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 302 ||
        response.body.contains('Your comment has been posted')) {
      return true;
    } else {
      return false;
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
                ? const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
            // Display the original comment being replied to.
            Row(
              children: [
                ClipRRect(
                  child: widget.comment['profileImage'] != null
                      ? CachedNetworkImage(
                    imageUrl: widget.comment['profileImage']!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 36,
                      height: 36,
                      color: Colors.grey,
                      child: const Icon(Icons.person, size: 24),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 36,
                      height: 36,
                      color: Colors.grey,
                      child: const Icon(Icons.person, size: 24),
                    ),
                  )
                      : Container(
                    width: 36,
                    height: 36,
                    color: Colors.grey,
                    child: const Icon(Icons.person, size: 24),
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
            Text(
              widget.comment['text'] ?? '',
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
