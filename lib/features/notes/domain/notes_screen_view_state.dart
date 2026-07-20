import 'package:fanotifier/features/notes/domain/message_model.dart';

class NotesScreenViewState {
  const NotesScreenViewState({
    required this.isLoadingInbox,
    required this.isLoadingMoreInbox,
    required this.errorInbox,
    required this.inboxMessages,
    required this.hasMoreInbox,
    required this.isLoadingSent,
    required this.isLoadingMoreSent,
    required this.errorSent,
    required this.sentMessages,
    required this.hasMoreSent,
    required this.isSelectionMode,
    required this.selectedIds,
  });

  factory NotesScreenViewState.initial() {
    return const NotesScreenViewState(
      isLoadingInbox: true,
      isLoadingMoreInbox: false,
      errorInbox: '',
      inboxMessages: <Message>[],
      hasMoreInbox: true,
      isLoadingSent: false,
      isLoadingMoreSent: false,
      errorSent: '',
      sentMessages: <Message>[],
      hasMoreSent: true,
      isSelectionMode: false,
      selectedIds: <String>{},
    );
  }

  final bool isLoadingInbox;
  final bool isLoadingMoreInbox;
  final String errorInbox;
  final List<Message> inboxMessages;
  final bool hasMoreInbox;
  final bool isLoadingSent;
  final bool isLoadingMoreSent;
  final String errorSent;
  final List<Message> sentMessages;
  final bool hasMoreSent;
  final bool isSelectionMode;
  final Set<String> selectedIds;

  NotesScreenViewState copyWith({
    bool? isLoadingInbox,
    bool? isLoadingMoreInbox,
    String? errorInbox,
    List<Message>? inboxMessages,
    bool? hasMoreInbox,
    bool? isLoadingSent,
    bool? isLoadingMoreSent,
    String? errorSent,
    List<Message>? sentMessages,
    bool? hasMoreSent,
    bool? isSelectionMode,
    Set<String>? selectedIds,
  }) {
    return NotesScreenViewState(
      isLoadingInbox: isLoadingInbox ?? this.isLoadingInbox,
      isLoadingMoreInbox: isLoadingMoreInbox ?? this.isLoadingMoreInbox,
      errorInbox: errorInbox ?? this.errorInbox,
      inboxMessages: inboxMessages == null
          ? this.inboxMessages
          : List<Message>.unmodifiable(inboxMessages),
      hasMoreInbox: hasMoreInbox ?? this.hasMoreInbox,
      isLoadingSent: isLoadingSent ?? this.isLoadingSent,
      isLoadingMoreSent: isLoadingMoreSent ?? this.isLoadingMoreSent,
      errorSent: errorSent ?? this.errorSent,
      sentMessages: sentMessages == null
          ? this.sentMessages
          : List<Message>.unmodifiable(sentMessages),
      hasMoreSent: hasMoreSent ?? this.hasMoreSent,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedIds: selectedIds == null
          ? this.selectedIds
          : Set<String>.unmodifiable(selectedIds),
    );
  }
}
