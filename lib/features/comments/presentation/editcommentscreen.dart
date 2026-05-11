import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:FANotifier/shared/fa/fa_edit_comment_service.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';

class EditCommentScreen extends StatefulWidget {
  final Map<String, dynamic> comment;
  final String editLink;
  final VoidCallback onUpdateComment;

  EditCommentScreen({
    required this.comment,
    required this.editLink,
    required this.onUpdateComment,
  });

  @override
  _EditCommentScreenState createState() => _EditCommentScreenState();
}

class _EditCommentScreenState extends State<EditCommentScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String? cookieA;
  String? cookieB;
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage(iOptions: IOSOptions( 
    accountName: 'flutter_secure_storage_service',
    accessibility: KeychainAccessibility.first_unlock));
  late FaEditCommentService _editCommentService;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.comment['text'];
    _editCommentService = FaEditCommentService();
    _loadCookies().then((_) => _loadEditForm());
  }

  @override
  void dispose() {
    _editCommentService.close();
    _controller.dispose();
    super.dispose();
  }
  Future<void> _loadEditForm() async {
    setState(() => _isLoading = true);

    final result = await _editCommentService.loadEditCommentText(
      editLink: widget.editLink,
      cookieA: cookieA,
      cookieB: cookieB,
    );

    if (result.errorMessage != null) {
      _showMessage(result.errorMessage!, isError: true);
    } else if (result.textarea != null) {
      _controller.text = result.textarea!;
    }

    setState(() => _isLoading = false);
  }


  Future<void> _loadCookies() async {
    cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    cookieB = await _secureStorage.read(key: 'fa_cookie_b');
    if (cookieA == null || cookieB == null) {
      _showMessage("Authentication cookies are missing.", isError: true);
    }
  }

  Future<void> _submitEdit() async {
    if (cookieA == null || cookieB == null) {
      _showMessage("Authentication cookies are missing.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final updatedText = _controller.text;

    final result = await _editCommentService.submitEditComment(
      editLink: widget.editLink,
      cookieA: cookieA,
      cookieB: cookieB,
      updatedText: updatedText,
      requireFValue: true,
      includeFValue: true,
    );

    if (result.success) {
      widget.onUpdateComment();
      _showMessage("Comment successfully updated!", isError: false);
      Navigator.pop(context);
    } else if (result.errorMessage != null) {
      _showMessage(result.errorMessage!, isError: true);
    }

    setState(() => _isLoading = false);
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Comment'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: Icon(Icons.save),
              onPressed: _submitEdit,
            ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: _isLoading
            ? Center(child: PulsatingLoadingIndicator(size: 108.0, assetPath: 'assets/icons/fathemed.png'))
            : TextField(
          controller: _controller,
          minLines: 6,
          maxLines: null,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'Edit your comment...',
            border: OutlineInputBorder(),
          ),
          contextMenuBuilder: BBCodeContextMenu.builder(_controller),
        ),
      ),
    );
  }
}
