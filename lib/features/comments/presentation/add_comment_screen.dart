import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:FANotifier/features/submissions/data/post_comment_service.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';

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
      bool success = await submitPostCommentOrReply(
        secureStorage: _secureStorage,
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




  Future<void> _onRequestClose() async {
    final confirmed = await ConfirmCloseDialog.show(context);
    if (confirmed && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) _onRequestClose();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onRequestClose,
          ),
          title: const Text("Add comment"),
          actions: [
            IconButton(
              icon: _isSending
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Icon(Icons.send),
              onPressed: _isSending ? null : _sendComment,
            ),
          ],
        ),
        body: SafeArea(
          bottom: true,
          maintainBottomViewPadding: true,
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
                  child: Scrollbar(
                    child: TextField(
                      controller: _commentController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
