import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AddCommentScreen extends StatefulWidget {
  final String submissionTitle;
  final Function(String) onSendComment;
  final String uniqueNumber;

  const AddCommentScreen({
    required this.submissionTitle,
    required this.onSendComment,
    required this.uniqueNumber,
    Key? key,
  }) : super(key: key);

  @override
  _AddCommentScreenState createState() => _AddCommentScreenState();
}

class _AddCommentScreenState extends State<AddCommentScreen> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();


  void _sendComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      bool success = await submitCommentOrReply(
        message: commentText,
        submissionId: widget.uniqueNumber,
      );

      if (success) {
        widget.onSendComment(commentText);
        Navigator.pop(context, true);


        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Comment posted!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error posting comment. Please try again.'),
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




  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<bool> submitCommentOrReply({
    required String message,
    String? submissionId,
    String? commentId,
  }) async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    String postUrl;
    Map<String, String> body;

    if (commentId != null) {

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

    final response = await http.post(
      Uri.parse(postUrl),
      headers: {
        'Cookie': 'a=$cookieA; b=$cookieB',
        'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );


    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');


    if (response.statusCode == 302 || response.body.contains('Your comment has been posted')) {
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
        title: const Text("Add comment"),
        actions: [
          IconButton(
            icon: _isSending
                ? const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            )
                : const Icon(Icons.send),
            onPressed: _isSending ? null : _sendComment,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              widget.submissionTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _commentController,
                style: const TextStyle(color: Colors.white),
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  hintText: 'Your comment',
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
