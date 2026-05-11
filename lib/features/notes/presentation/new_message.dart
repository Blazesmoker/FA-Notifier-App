import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:FANotifier/features/notes/data/new_message_service.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';

class NewMessageScreen extends StatelessWidget {
  final TextEditingController _recipientController;
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  NewMessageScreen({Key? key, String? recipient})
      : _recipientController = TextEditingController(text: recipient ?? ''),
        super(key: key);


  final _newMessageService = NewMessageService(
    secureStorage: const FlutterSecureStorage(
      iOptions: IOSOptions(
        accountName: 'flutter_secure_storage_service',
        accessibility: KeychainAccessibility.first_unlock,
      ),
    ),
  );

  Future<void> _sendMessage(BuildContext context) async {
    final result = await _newMessageService.sendMessage(
      recipient: _recipientController.text.trim(),
      subject: _subjectController.text.trim(),
      message: _messageController.text.trim(),
    );

    if (result.message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message!),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    }

    if (result.success) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    Future<void> onRequestClose() async {
      final confirmed = await ConfirmCloseDialog.show(context);
      if (confirmed && context.mounted) Navigator.pop(context);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) onRequestClose();
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onRequestClose,
        ),
        title: const Text("Compose New Message", overflow: TextOverflow.visible,),
        actions: [
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendMessage(context),
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _recipientController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Recipient',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _subjectController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Subject',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          minLines: 6,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Your Message',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          contextMenuBuilder: BBCodeContextMenu.builder(_messageController),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ));

  }

}
