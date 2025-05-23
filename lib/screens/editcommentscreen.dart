import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import '../widgets/PulsatingLoadingIndicator.dart';

class EditCommentScreen extends StatefulWidget {
  final Map<String, dynamic> comment;
  final String editLink;
  final Function(String) onUpdateComment;

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
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  late http.Client _client;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.comment['text'];
    _client = http.Client();
    _loadCookies();
  }

  @override
  void dispose() {
    _client.close();
    _controller.dispose();
    super.dispose();
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

    try {

      final getResponse = await _client.get(
        Uri.parse(widget.editLink),
        headers: {
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': 'FANotifier/1.0',
          'Referer': widget.editLink,
        },
      );

      if (getResponse.statusCode != 200) {
        _showMessage("Failed to load edit page. Status code: ${getResponse.statusCode}", isError: true);
        setState(() => _isLoading = false);
        return;
      }


      final document = html_parser.parse(getResponse.body);
      final form = document.querySelector('form#edit_comment_form');

      if (form == null) {
        _showMessage("Edit form not found on the page.", isError: true);
        setState(() => _isLoading = false);
        return;
      }


      String? action = form.attributes['action'];
      String? commentId = form.querySelector('input[name="comment_id"]')?.attributes['value'];
      String? csrfKey = form.querySelector('input[name="key"]')?.attributes['value'];
      String? fValue = form.querySelector('input[name="f"]')?.attributes['value'];

      if (action == null || commentId == null || csrfKey == null || fValue == null) {
        _showMessage("Required form fields are missing.", isError: true);
        setState(() => _isLoading = false);
        return;
      }

      // Full URL for the POST request
      Uri postUri = action.startsWith('http')
          ? Uri.parse(action)
          : Uri.parse('https://www.furaffinity.net$action');

      // Submit the POST request with all form data
      final postResponse = await _client.post(
        postUri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Cookie': 'a=$cookieA; b=$cookieB',
          'User-Agent': 'YourAppName/1.0',
          'Referer': widget.editLink,
        },
        body: {
          'action': 'edit-comment',
          'comment_id': commentId,
          'key': csrfKey,
          'f': fValue,
          'message': updatedText,
          'mysubmit': 'Save',
        },
      );

      if (postResponse.statusCode == 302) {
        widget.onUpdateComment(updatedText);
        _showMessage("Comment successfully updated!", isError: false);
        Navigator.pop(context);
      } else {
        _showMessage("Failed to update comment. Status code: ${postResponse.statusCode}", isError: true);
      }
    } catch (error) {
      _showMessage("An error occurred: $error", isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
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
          decoration: InputDecoration(
            hintText: 'Edit your comment...',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
