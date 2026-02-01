import 'package:flutter/material.dart';

import '../widgets/PulsatingLoadingIndicator.dart';
import 'message_model.dart';

class MessageList extends StatelessWidget {
  static const Color _accent = Color(0xFFE09321);

  final bool isLoading;
  final bool isLoadingMore;
  final String errorMessage;
  final List<Message> messages;
  final String folder;
  final ScrollController scrollController;
  final bool hasMore;
  final Future<void> Function() refreshInbox;
  final Future<void> Function() refreshSent;
  final Future<void> Function() loadMore;
  final void Function(Message msg) onOpenMessage;
  final void Function(Message msg)? onPreviewMessage;

  const MessageList({
    Key? key,
    required this.isLoading,
    required this.isLoadingMore,
    required this.errorMessage,
    required this.messages,
    required this.folder,
    required this.scrollController,
    required this.hasMore,
    required this.refreshInbox,
    required this.refreshSent,
    required this.loadMore,
    required this.onOpenMessage,
    this.onPreviewMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final onRefresh = () async {
      if (folder == 'inbox') {
        await refreshInbox();
      } else {
        await refreshSent();
      }
    };


    if (isLoading && messages.isEmpty) {
      return RefreshIndicator(
        color: _accent,
        backgroundColor: Colors.black,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Center(
              child: PulsatingLoadingIndicator(
                size: 108.0,
                assetPath: 'assets/icons/fathemed.png',
              ),
            ),
          ],
        ),
      );
    }

    if (errorMessage.isNotEmpty && messages.isEmpty) {
      return RefreshIndicator(
        color: _accent,
        backgroundColor: Colors.black,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 180),
            Center(
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    if (messages.isEmpty) {
      return RefreshIndicator(
        color: _accent,
        backgroundColor: Colors.black,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Center(
              child: Text(
                'No messages found.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _accent,
      backgroundColor: Colors.black,
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: messages.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 44.0),
              child: Center(
                child: isLoadingMore
                    ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(_accent),
                  ),
                )
                    : const SizedBox.shrink(),
              ),
            );
          }

          final msg = messages[index];
          return GestureDetector(
            onTap: () => onOpenMessage(msg),
            child: Column(
              children: [
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8.0,
                    horizontal: 16.0,
                  ),
                  child: Row(
                    children: [
                      if (msg.isUnread)
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 16),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _accent,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.subject,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),

                            Text(
                              'From: ${msg.sender}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Date: ${msg.date}',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (folder == 'inbox' && onPreviewMessage != null)
                        IconButton(
                          icon: const Icon(Icons.preview, color: Colors.white),
                          tooltip: 'Preview',
                          onPressed: () => onPreviewMessage!(msg),
                        ),
                    ],
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 0.2,
                  color: Colors.grey,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
