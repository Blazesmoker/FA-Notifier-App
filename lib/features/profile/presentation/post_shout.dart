import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:FANotifier/features/profile/data/shout_service.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';

class PostShoutScreen extends StatefulWidget {
  final String username;

  const PostShoutScreen({Key? key, required this.username}) : super(key: key);

  @override
  _PostShoutScreenState createState() => _PostShoutScreenState();
}

class _PostShoutScreenState extends State<PostShoutScreen> {
  final TextEditingController _shoutController = TextEditingController();
  late final ShoutService _shoutService;

  final int _maxLength = 222;
  bool _isLoading = false;
  final ValueNotifier<int> _lengthNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _shoutService = ShoutService();
    _shoutService.initialize();
    _shoutController.addListener(() {
      // Only update when TEXT changes, not selection
      final newLength = _shoutController.text.length;
      if (_lengthNotifier.value != newLength) {
        _lengthNotifier.value = newLength;
      }

      if (newLength > _maxLength) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Too many characters!')),
        );
      }
    });
  }

  @override
  void dispose() {
    _shoutService.close();
    _shoutController.dispose();
    _lengthNotifier.dispose();
    super.dispose();
  }

  Future<void> _postShout() async {
    // Check for empty shout
    if (_shoutController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a shout.')),
      );
      return;
    }
    // Check if text length exceeds the limit before posting.
    if (_shoutController.text.trim().length > _maxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot send more than 222 characters!')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await _shoutService.postShout(
      username: widget.username,
      shout: _shoutController.text.trim(),
    );

    if (result.message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message!),
          backgroundColor: result.isError
              ? Colors.red
              : result.success
                  ? Colors.green
                  : null,
        ),
      );
    }

    if (result.success) {
      Navigator.pop(context, true);
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _onRequestClose() async {
    final confirmed = await ConfirmCloseDialog.show(context);
    if (confirmed && mounted) Navigator.pop(context);
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
          title: const Text("Compose Shout"),
          actions: [
            _isLoading
                ? Padding(
              padding: const EdgeInsets.all(12.0),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
                : IconButton(
              icon: const Icon(Icons.send),
              onPressed: _postShout,
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: TextField(
                    controller: _shoutController,
                    minLines: 6,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(color: Colors.white),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_maxLength),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Your Shout',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      counterText: null,
                      counter: ValueListenableBuilder<int>(
                        valueListenable: _lengthNotifier,
                        builder: (context, length, child) {
                          return Text('$length/$_maxLength');
                        },
                      ),
                    ),
                    contextMenuBuilder: BBCodeContextMenu.builder(_shoutController),
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
