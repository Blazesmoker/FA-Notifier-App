import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/comments/domain/comment_edit_repository.dart';
import 'package:fanotifier/shared/utils/bbcode_context_menu.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';

class EditJournalCommentScreen extends StatefulWidget {
  final Map<String, dynamic> comment;
  final String editLink;
  final VoidCallback onUpdateComment;
  final CommentEditRepository? commentEditRepository;

  const EditJournalCommentScreen({
    super.key,
    required this.comment,
    required this.editLink,
    required this.onUpdateComment,
    this.commentEditRepository,
  });

  @override
  State<EditJournalCommentScreen> createState() =>
      _EditJournalCommentScreenState();
}

class _EditJournalCommentScreenState extends State<EditJournalCommentScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  late final CommentEditRepository _editCommentRepository;
  late final bool _ownsEditCommentRepository;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.comment['text'];
    _ownsEditCommentRepository = widget.commentEditRepository == null;
    _editCommentRepository = widget.commentEditRepository ??
        context.read<CommentEditRepositoryFactory>()();
    _loadEditForm();
  }

  @override
  void dispose() {
    if (_ownsEditCommentRepository) {
      _editCommentRepository.close();
    }
    _controller.dispose();
    super.dispose();
  }
  Future<void> _loadEditForm() async {
    setState(() => _isLoading = true);

    final result = await _editCommentRepository.loadEditCommentText(
      editLink: widget.editLink,
    );

    if (!mounted) return;
    if (result.errorMessage != null) {
      _showMessage(result.errorMessage!, isError: true);
    } else if (result.textarea != null) {
      _controller.text = result.textarea!;
    }

    setState(() => _isLoading = false);
  }


  Future<void> _submitEdit() async {
    setState(() => _isLoading = true);

    final updatedText = _controller.text;

    final result = await _editCommentRepository.submitEditComment(
      editLink: widget.editLink,
      updatedText: updatedText,
      requireFValue: false,
      includeFValue: false,
      logFormDebug: true,
    );

    if (!mounted) return;
    if (result.success) {
      widget.onUpdateComment();
      _showMessage("Comment successfully updated!", isError: false);
      Navigator.pop(context);
    } else if (result.errorMessage != null) {
      _showMessage(result.errorMessage!, isError: true);
    }

    if (mounted) setState(() => _isLoading = false);
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
          maxLines: null,
          minLines: 6,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: const InputDecoration(
            hintText: 'Edit your comment...',
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(),
          ),
          contextMenuBuilder: BBCodeContextMenu.builder(_controller),
        ),

      ),
    );
  }
}
