import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/notes/domain/message_model.dart';
import 'package:fanotifier/features/notes/presentation/notesscreen_widgets.dart';

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
  final bool isSelectionMode;
  final Set<String> selectedIds;
  final void Function(Message msg) onLongPressItem;
  final void Function(Message msg) onTapItem;

  const InboxTab({
    super.key,
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
    required this.isSelectionMode,
    required this.selectedIds,
    required this.onLongPressItem,
    required this.onTapItem,
  });

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
      isSelectionMode: isSelectionMode,
      selectedIds: selectedIds,
      onLongPressItem: onLongPressItem,
      onTapItem: onTapItem,
    );
  }
}
