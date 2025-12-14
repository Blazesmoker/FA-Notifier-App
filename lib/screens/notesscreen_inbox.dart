import 'package:flutter/material.dart';

import 'message_model.dart';
import 'notesscreen_widgets.dart';

class InboxTab extends StatelessWidget {
  final bool isLoading;
  final bool isLoadingMore;
  final String errorMessage;
  final List<Message> messages;
  final ScrollController scrollController;
  final bool hasMore;
  final Future<void> Function() refreshInbox;
  final Future<void> Function() refreshSent;
  final Future<void> Function() loadMore;
  final void Function(Message msg) onOpenMessage;
  final void Function(Message msg) onPreviewMessage;

  const InboxTab({
    Key? key,
    required this.isLoading,
    required this.isLoadingMore,
    required this.errorMessage,
    required this.messages,
    required this.scrollController,
    required this.hasMore,
    required this.refreshInbox,
    required this.refreshSent,
    required this.loadMore,
    required this.onOpenMessage,
    required this.onPreviewMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MessageList(
      isLoading: isLoading,
      isLoadingMore: isLoadingMore,
      errorMessage: errorMessage,
      messages: messages,
      folder: 'inbox',
      scrollController: scrollController,
      hasMore: hasMore,
      refreshInbox: refreshInbox,
      refreshSent: refreshSent,
      loadMore: loadMore,
      onOpenMessage: onOpenMessage,
      onPreviewMessage: onPreviewMessage,
    );
  }
}
