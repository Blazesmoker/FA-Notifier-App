import 'dart:async';

import 'package:flutter/material.dart';

import 'package:FANotifier/features/notes/domain/new_message_repository.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:FANotifier/shared/widgets/cooldown_send_icon.dart';
import 'package:provider/provider.dart';

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({Key? key, this.recipient}) : super(key: key);

  final String? recipient;

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  late final TextEditingController _recipientController =
      TextEditingController(text: widget.recipient ?? '');
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  late final NewMessageRepository _newMessageRepository;

  Timer? _cooldownTimer;
  bool _isSending = false;
  int _cooldownRemaining = 0;
  int _cooldownTotal = 0;

  @override
  void initState() {
    super.initState();
    _newMessageRepository = context.read<NewMessageRepositoryFactory>()();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _recipientController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (_isSending || _cooldownRemaining > 0) return;

    setState(() {
      _isSending = true;
    });

    final result = await _newMessageRepository.sendMessage(
      recipient: _recipientController.text.trim(),
      subject: _subjectController.text.trim(),
      message: _messageController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isSending = false;
    });

    final retryAfter = result.retryAfterSeconds;
    final isWaitingToRetry =
        !result.success && retryAfter != null && retryAfter > 0;

    if (result.message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message!),
          backgroundColor: result.success ? Colors.green : Colors.red,
          duration: isWaitingToRetry
              ? const Duration(seconds: 6)
              : const Duration(seconds: 4),
        ),
      );
    }

    if (!result.success && retryAfter != null && retryAfter > 0) {
      _startCooldown(retryAfter);
    }

    if (result.success) {
      Navigator.pop(context);
    }
  }

  void _startCooldown(int seconds) {
    if (!mounted) return;
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownTotal = seconds;
      _cooldownRemaining = seconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownRemaining <= 1) {
        timer.cancel();
        setState(() {
          _cooldownRemaining = 0;
          _cooldownTotal = 0;
        });
      } else {
        setState(() {
          _cooldownRemaining--;
        });
      }
    });
  }

  Widget _buildSendIcon() {
    if (_isSending) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          strokeWidth: 2.0,
        ),
      );
    }
    if (_cooldownRemaining > 0) {
      return CooldownSendIcon(
        remainingSeconds: _cooldownRemaining,
        totalSeconds: _cooldownTotal,
      );
    }
    return const Icon(Icons.send);
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
          title: const Text(
            "Compose New Message",
            overflow: TextOverflow.visible,
          ),
          actions: [
            IconButton(
              icon: _buildSendIcon(),
              onPressed:
                  (_isSending || _cooldownRemaining > 0) ? null : _sendMessage,
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
                            contextMenuBuilder:
                                BBCodeContextMenu.builder(_messageController),
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
      ),
    );
  }
}
