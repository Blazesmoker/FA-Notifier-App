import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';

class AddJournalCommentScreen extends StatefulWidget {
  final String submissionTitle;
  final Function(String) onSendComment;
  final String uniqueNumber; // This is the submissionId

  const AddJournalCommentScreen({
    required this.submissionTitle,
    required this.onSendComment,
    required this.uniqueNumber,
    Key? key,
  }) : super(key: key);

  @override
  _AddCommentScreenState createState() => _AddCommentScreenState();
}

class _AddCommentScreenState extends State<AddJournalCommentScreen> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSending = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock));


  void _sendComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      bool success = await submitCommentOrReply(
        message: commentText,
        journalId: widget.uniqueNumber,
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




  Future<void> _onRequestClose() async {
    final confirmed = await ConfirmCloseDialog.show(context);
    if (confirmed && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<bool> submitCommentOrReply({
    required String message,
    required String journalId,
    String? replyToId,
  }) async {

    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');


    if (cookieA == null || cookieB == null) {
      debugPrint('Error: Authentication cookies are missing.');
      return false;
    }

    String postUrl = 'https://www.furaffinity.net/journal/$journalId/';

    Map<String, String> body = {
      'action': 'reply',
      'replyto': replyToId ?? '',
      'reply': message,
      'submit': 'Post Comment',
    };

    final response = await http.post(
      Uri.parse(postUrl),
      headers: {
        'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
          'a=$cookieA; b=$cookieB',
        ),
        'User-Agent': FAHttp.userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'en-US,en;q=0.5',
      },
      body: body,
    );


    debugPrint('Status Code: ${response.statusCode}');



    if (response.statusCode == 302) {

      return true;
    } else if (response.statusCode == 200 && response.body.contains('Your comment has been posted')) {
      return true;
    } else {
      debugPrint('Failed to post comment. Response status: ${response.statusCode}');
      return false;
    }
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
          title: const Text("Add Comment"),
          actions: [
            IconButton(
              icon: _isSending
                  ? const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2.0,
                ),
              )
                  : const Icon(Icons.send),
              onPressed: _isSending ? null : _sendComment,
            ),
          ],
        ),
        body: SafeArea(
          bottom: true,
          child: Padding(
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
                    contextMenuBuilder: BBCodeContextMenu.builder(_commentController),
                    textInputAction: TextInputAction.newline,
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
