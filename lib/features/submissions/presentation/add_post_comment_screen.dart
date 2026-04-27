import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';

Future<bool> submitPostCommentOrReply({
  required FlutterSecureStorage secureStorage,
  required String message,
  String? submissionId,
  String? commentId,
}) async {
  final cookieA = await secureStorage.read(key: 'fa_cookie_a');
  final cookieB = await secureStorage.read(key: 'fa_cookie_b');

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
      'Cookie': await FaCookieHelper.appendCfClearanceToCookieHeader(
        'a=$cookieA; b=$cookieB',
      ),
      'User-Agent': FAHttp.userAgent,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: body,
  );

  debugPrint('Status Code: ${response.statusCode}');
  debugPrint('Response Body: ${response.body}');

  return response.statusCode == 302 ||
      response.body.contains('Your comment has been posted');
}

class AddPostCommentScreen extends StatefulWidget {
  final String submissionTitle;
  final Function(String) onSendComment;
  final String uniqueNumber;

  const AddPostCommentScreen({
    required this.submissionTitle,
    required this.onSendComment,
    required this.uniqueNumber,
    Key? key,
  }) : super(key: key);

  @override
  State<AddPostCommentScreen> createState() => _AddPostCommentScreenState();
}

class _AddPostCommentScreenState extends State<AddPostCommentScreen>
    with WidgetsBindingObserver {
  final TextEditingController _commentController = TextEditingController();
  final ValueNotifier<double> _keyboardInset = ValueNotifier<double>(0);
  final ValueNotifier<double> _navBarInset = ValueNotifier<double>(0);
  bool _isSending = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateKeyboardInset();
    });
  }

  Future<void> _sendComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final success = await submitPostCommentOrReply(
        secureStorage: _secureStorage,
        message: commentText,
        submissionId: widget.uniqueNumber,
      );

      if (!mounted) return;

      if (success) {
        widget.onSendComment(commentText);
        Navigator.pop(context, true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment posted!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error posting comment. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _onRequestClose() async {
    final confirmed = await ConfirmCloseDialog.show(context);
    if (confirmed && mounted) Navigator.pop(context);
  }

  @override
  void didChangeMetrics() {
    _updateKeyboardInset();
  }

  void _updateKeyboardInset() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final keyboardInset = view.viewInsets.bottom / view.devicePixelRatio;
    final navBarInset = view.viewPadding.bottom / view.devicePixelRatio;
    if ((keyboardInset - _keyboardInset.value).abs() > 0.5) {
      _keyboardInset.value = keyboardInset;
    }
    if ((navBarInset - _navBarInset.value).abs() > 0.5) {
      _navBarInset.value = navBarInset;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardInset.dispose();
    _navBarInset.dispose();
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
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onRequestClose,
          ),
          title: const Text('Add comment'),
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
          bottom: false,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _keyboardInset,
              _navBarInset,
            ]),
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
                        minLines: 6,
                        maxLines: null,
                        scrollPadding: const EdgeInsets.only(bottom: 8),
                        decoration: const InputDecoration(
                          hintText: 'Your comment',
                          hintStyle: TextStyle(color: Colors.white70),
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        contextMenuBuilder:
                            BBCodeContextMenu.builder(_commentController),
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            builder: (context, child) {
              final keyboardInset = _keyboardInset.value;
              final navBarInset = _navBarInset.value;
              final bottomInset =
                  keyboardInset > 0 ? keyboardInset : navBarInset;
              return Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }
}
