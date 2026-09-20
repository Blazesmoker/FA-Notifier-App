import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'widgets/message_detail_actions.dart';
import 'widgets/message_detail_header.dart';
import 'widgets/message_detail_status.dart';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:fanotifier/features/notes/domain/note_message_repository.dart';
import 'package:fanotifier/features/notes/domain/managed_notes_repository.dart';
import 'package:fanotifier/features/notes/domain/note_management.dart';
import 'package:fanotifier/features/notes/domain/notes_refresh_port.dart';
import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:fanotifier/features/notes/presentation/note_reply_screen.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/notes/domain/note_image_preview_mode.dart';
import 'package:fanotifier/features/notes/domain/note_submission_preview_repository.dart';
import 'package:fanotifier/features/notes/presentation/note_body_with_previews.dart';
import 'package:fanotifier/features/notes/presentation/note_image_preview_settings_provider.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/utils/app_snack_bar.dart';
import 'package:fanotifier/shared/utils/bbcode_context_menu.dart';
import 'package:fanotifier/shared/translation/native_translate_launcher.dart';
import 'package:fanotifier/core/preferences/translator_settings_provider.dart';
import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/presentation/time_display_settings_provider.dart';
import 'package:provider/provider.dart';

enum _MessageMenuAction {
  archive,
  trash,
  translate,
}

class MessageDetailScreen extends StatefulWidget {
  final String messageLink;
  final String folder;
  final bool allowMarkUnread;
  final NotesFolder sourceFolder;

  const MessageDetailScreen({
    super.key,
    required this.messageLink,
    required this.folder,
    required this.sourceFolder,
    this.allowMarkUnread = true,
  });

  @override
  State<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
  late final NoteMessageRepository _noteMessageRepository;
  late final ManagedNotesRepository _managedNotesRepository;
  late final NotesRefreshPort _notesRefreshPort;

  bool isLoading = true;
  String errorMessage = '';
  String subject = '';
  String sender = '';
  String recipient = '';
  String sentDate = '';
  String avatarUrl = '';
  String messageContent = '';
  String messageContentHtml = '';
  String? messageId;
  String senderUsername = '';
  String senderLink = '';
  String recipientLink = '';
  String recipientUsername = '';
  int pageNumber = 1;
  bool isClassic = false;
  bool _shouldShowReplySuccess = false;
  bool _didTriggerRefreshOnExit = false;
  bool _isMutating = false;
  String _selectedMessageText = '';

  @override
  void initState() {
    super.initState();
    _noteMessageRepository = context.read<NoteMessageRepositoryFactory>()();
    _managedNotesRepository = context.read<ManagedNotesRepositoryFactory>()();
    _notesRefreshPort = context.read<NotesRefreshPort>();
    _fetchMessageDetails();
  }

  @override
  void dispose() {
    _noteMessageRepository.close();
    super.dispose();
  }

  Future<void> _fetchMessageDetails() async {
    try {
      final result = await _noteMessageRepository.fetchMessageDetails(
        messageLink: widget.messageLink,
        folder: widget.folder,
      );

      if (!mounted) return;
      if (result.redirected) {
        setState(() {
          errorMessage = 'Redirected. Possibly authentication issues.';
          isLoading = false;
        });
        return;
      }

      final details = result.details;
      if (details != null) {

        setState(() {
          isClassic = details.isClassic;
          messageId = details.messageId;
          pageNumber = details.pageNumber;
          subject = details.subject;
          sender = details.sender;
          recipient = details.recipient;
          sentDate = details.sentDate;
          avatarUrl = details.avatarUrl;
          messageContent = details.messageContent;
          messageContentHtml = details.messageContentHtml;
          senderLink = details.senderLink;
          senderUsername = details.senderUsername;
          recipientLink = details.recipientLink;
          recipientUsername = details.recipientUsername;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to fetch message: ${result.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'An error occurred: $e';
        isLoading = false;
      });
    }
  }


  Future<void> _markAsUnread() async {
    if (messageId == null) return;
    try {
      final statusCode = await _noteMessageRepository.markAsUnread(
        folder: widget.folder,
        messageId: messageId!,
        pageNumber: pageNumber,
      );

      if (!mounted) return;
      if (statusCode == 302 || statusCode == 200) {
        showAppSnackBar(context, 'Message marked as unread');
        _triggerNotesRefreshOnce();
        Navigator.pop(context, 'marked_unread');
      } else {
        setState(() {
          errorMessage = 'Failed to mark as unread: $statusCode';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'An error occurred: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  GlobalKey _selectableKey = GlobalKey();

  void _triggerNotesRefreshOnce() {
    if (_didTriggerRefreshOnExit) return;
    _didTriggerRefreshOnExit = true;
    _notesRefreshPort.triggerRefresh();
  }

  void _clearSelection() {
    setState(() {
      // Generates a new key to force the selectable widget to rebuild without a selection.
      _selectableKey = GlobalKey();
    });
    _selectedMessageText = '';
  }

  void _updatePlainMessageSelection(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    if (!selection.isValid || selection.isCollapsed) {
      _selectedMessageText = '';
      return;
    }
    final start =
        selection.start < selection.end ? selection.start : selection.end;
    final end =
        selection.start < selection.end ? selection.end : selection.start;
    _selectedMessageText = messageContent.substring(start, end);
  }

  Future<void> _openMessageTranslation() async {
    final text = messageContent.trim();
    if (text.isEmpty) return;
    final translatorSettings = context.read<TranslatorSettingsProvider>();
    await NativeTranslateLauncher.open(
      text,
      targetLanguageCode: translatorSettings.targetLanguageCode,
    );
  }

  Future<void> _moveMessage(_MessageMenuAction menuAction) async {
    final id = messageId;
    if (id == null || _isMutating) return;
    final destination = menuAction == _MessageMenuAction.archive
        ? 'Archive'
        : 'Trash';
    final action = menuAction == _MessageMenuAction.archive
        ? NoteManagementAction.moveToArchive
        : NoteManagementAction.moveToTrash;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'Move to $destination',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'Move this note to $destination?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              destination,
              style: const TextStyle(
                color: Color(0xFFE09321),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isMutating = true);
    try {
      await _managedNotesRepository.applyAction(
        ids: [id],
        sourceFolder: widget.sourceFolder,
        action: action,
      );
      if (!mounted) return;
      setState(() => _isMutating = false);
      final messenger = ScaffoldMessenger.of(context);
      _triggerNotesRefreshOnce();
      Navigator.of(context).pop('refresh');
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Moved 1 note to $destination.'),
          backgroundColor: Colors.green,
        ),
      );
    } on NoteManagementOutcomeUnknownException {
      if (mounted) {
        _showManagementSnackBar(
          'Could not confirm whether 1 note was moved to $destination.',
          success: false,
        );
      }
    } catch (_) {
      if (mounted) {
        _showManagementSnackBar(
          'Failed to move 1 note to $destination.',
          success: false,
        );
      }
    } finally {
      if (mounted && _isMutating) setState(() => _isMutating = false);
    }
  }

  void _showManagementSnackBar(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imagePreviewSettings =
        context.watch<NoteImagePreviewSettingsProvider>();
    final timeFormat =
        context.select<TimeDisplaySettingsProvider, TimeDisplayFormat>(
      (settings) => settings.formatFor(TimeDisplayOccasion.noteDetail),
    );
    final imagePreviewMode = imagePreviewSettings.loaded
        ? imagePreviewSettings.mode
        : NoteImagePreviewMode.off;
    final hasImagePreviewLinks =
        imagePreviewMode != NoteImagePreviewMode.off &&
            noteBodyContainsPreviewLinks(
              messageContentHtml.isNotEmpty
                  ? messageContentHtml
                  : messageContent,
              isHtml: messageContentHtml.isNotEmpty,
            );
    final imagePreviewRepository = hasImagePreviewLinks
        ? context.read<NoteSubmissionPreviewRepository>()
        : null;
    final bottomSafeInset = MediaQuery.paddingOf(context).bottom;
    final messageActionsFadeBottomInset =
        bottomSafeInset + messageActionsFadeBottomOffset;
    final messageActionsButtonsBottomInset =
        bottomSafeInset + messageActionsButtonsBottomOffset;
    final messageActionsContentBottomInset = math.max(
      messageActionsFadeBottomInset,
      messageActionsButtonsBottomInset,
    );
    if (_shouldShowReplySuccess) {
      _shouldShowReplySuccess = false; // Reset immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint('DEBUG: Showing snackbar from build cycle');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reply sent successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (TapUpDetails details) {
        final RenderBox? renderBox = _selectableKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          // Convert the global tap position to local coordinates of the selectable widget.
          final Offset localPosition = renderBox.globalToLocal(details.globalPosition);
          // If the tap is outside the selectable widget’s bounds, clear the selection.
          if (!renderBox.size.contains(localPosition)) {
            _clearSelection();
          }
        } else {
          _clearSelection();
        }
      },
      child: PopScope(
        canPop: !_isMutating,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop) return;
          _triggerNotesRefreshOnce();
        },
        child: SafeArea(
          top: false,
          bottom: false,
          child: Scaffold(
            appBar: AppBar(
              title: Text(subject),
              backgroundColor: Colors.black,
              actions: [
                Builder(
                  builder: (context) {
                    return IconButton(
                      icon: Icon(
                        Icons.more_vert,
                        color: _isMutating ? Colors.grey : Colors.white,
                      ),
                      onPressed: _isMutating
                          ? null
                          : () async {
                        final RenderBox button =
                            context.findRenderObject() as RenderBox;
                        final RenderBox overlay = Overlay.of(context)
                            .context
                            .findRenderObject() as RenderBox;
                        final RelativeRect position = RelativeRect.fromRect(
                          Rect.fromPoints(
                            button.localToGlobal(
                              Offset(0, button.size.height),
                              ancestor: overlay,
                            ),
                            button.localToGlobal(
                              button.size.bottomRight(
                                Offset(0, button.size.height + 10),
                              ),
                              ancestor: overlay,
                            ),
                          ),
                          Offset.zero & overlay.size,
                        );

                        final selected = await showMenu<_MessageMenuAction>(
                          context: context,
                          position: position,
                          items: [
                            buildMessageDetailMenuItem(
                              action: _MessageMenuAction.archive,
                              icon: Icons.archive_outlined,
                              label: 'Move to Archive',
                              enabled:
                                  messageId != null &&
                                  widget.sourceFolder !=
                                      NotesFolder.archive,
                            ),
                            buildMessageDetailMenuItem(
                              action: _MessageMenuAction.trash,
                              icon: Icons.delete_outline,
                              label: 'Move to Trash',
                              enabled:
                                  messageId != null &&
                                  widget.sourceFolder !=
                                      NotesFolder.trash,
                            ),
                            buildMessageDetailMenuItem(
                              action: _MessageMenuAction.translate,
                              icon: Icons.g_translate,
                              label: 'Translate',
                              enabled: messageContent
                                  .trim()
                                  .isNotEmpty,
                            ),
                          ],
                        );
                        switch (selected) {
                          case _MessageMenuAction.archive:
                          case _MessageMenuAction.trash:
                            await _moveMessage(selected!);
                            break;
                          case _MessageMenuAction.translate:
                            await _openMessageTranslation();
                            break;
                          case null:
                            break;
                        }
                      },
                    );
                  },
                ),
              ],
            ),
            backgroundColor: Colors.black,
            body: isLoading
                ? buildMessageDetailLoading()
                : errorMessage.isNotEmpty
                ? buildMessageDetailError(errorMessage)
                : Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                top: 16.0,
                right: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildMessageDetailHeader(
                    isClassic: isClassic,
                    avatarUrl: avatarUrl,
                    sender: sender,
                    recipient: recipient,
                    senderLink: senderLink,
                    recipientLink: recipientLink,
                    sentDate: sentDate,
                    timeFormat: timeFormat,
                    folder: widget.folder,
                    onAvatarTap: () {
                      final link = widget.folder == 'sent'
                          ? recipientLink
                          : senderLink;
                      if (link.isNotEmpty) {
                        handleFALink(context, link);
                      }
                    },
                    onSenderTap: () => handleFALink(context, senderLink),
                    onRecipientTap: () =>
                        handleFALink(context, recipientLink),
                  ),
                  const Divider(height: 20, thickness: 1, color: Colors.white54),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.only(
                              bottom: widget.folder != 'sent'
                                  ? messageActionsScrollClearance +
                                      messageActionsContentBottomInset
                                  : messageActionsFadeBottomInset,
                            ),
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                textSelectionTheme: TextSelectionThemeData(
                                  selectionColor: const Color(0xFFE09321)
                                      .withValues(alpha: 0.4),
                                  selectionHandleColor:
                                      const Color(0xFFE09321),
                                ),
                              ),
                              child: hasImagePreviewLinks
                                  ? SelectionArea(
                                      key: _selectableKey,
                                      onSelectionChanged: (content) {
                                        _selectedMessageText = content?.plainText
                                                .replaceAll('\uFFFC', '') ??
                                            '';
                                      },
                                      contextMenuBuilder:
                                          ReadOnlySelectionContextMenu.builder(
                                        selectedTextProvider: () =>
                                            _selectedMessageText,
                                        includeIosTranslate: true,
                                      ),
                                      child: NoteBodyWithPreviews(
                                        content: messageContentHtml.isNotEmpty
                                            ? messageContentHtml
                                            : messageContent,
                                        isHtml:
                                            messageContentHtml.isNotEmpty,
                                        mode: imagePreviewMode,
                                        repository: imagePreviewRepository!,
                                      ),
                                    )
                            : messageContentHtml.isNotEmpty
                            ? SelectionArea(
                                key: _selectableKey,
                                onSelectionChanged: (content) {
                                  _selectedMessageText =
                                      content?.plainText ?? '';
                                },
                                contextMenuBuilder:
                                    ReadOnlySelectionContextMenu.builder(
                                  selectedTextProvider: () =>
                                      _selectedMessageText,
                                  includeIosTranslate: true,
                                ),
                                child: html_pkg.Html(
                                  data: messageContentHtml,
                                  style: {
                                    'body': html_pkg.Style(
                                      margin: html_pkg.Margins.zero,
                                      padding: html_pkg.HtmlPaddings.zero,
                                      color: Colors.white,
                                      fontSize: html_pkg.FontSize(16),
                                    ),
                                    'b': html_pkg.Style(fontWeight: FontWeight.bold),
                                    'strong': html_pkg.Style(fontWeight: FontWeight.bold),
                                    'i': html_pkg.Style(fontStyle: FontStyle.italic),
                                    '.bbcode_i': html_pkg.Style(fontStyle: FontStyle.italic),
                                    'u': html_pkg.Style(textDecoration: TextDecoration.underline),
                                    '.bbcode_u': html_pkg.Style(textDecoration: TextDecoration.underline),
                                    '.bbcode_center': html_pkg.Style(
                                      display: html_pkg.Display.block,
                                      textAlign: TextAlign.center,
                                    ),
                                    '.bbcode_left': html_pkg.Style(
                                      display: html_pkg.Display.block,
                                      textAlign: TextAlign.left,
                                    ),
                                    '.bbcode_right': html_pkg.Style(
                                      display: html_pkg.Display.block,
                                      textAlign: TextAlign.right,
                                    ),
                                    'a': html_pkg.Style(
                                      color: const Color(0xFFE09321),
                                      textDecoration: TextDecoration.none,
                                    ),
                                  },
                                  onLinkTap: (url, _, _) {
                                    if (url != null) handleFALink(context, url);
                                  },
                                  extensions: [faHtmlImageExtension()],
                                ),
                                        )
                                      : SelectableLinkify(
                                key: _selectableKey,
                                onSelectionChanged:
                                    _updatePlainMessageSelection,
                                contextMenuBuilder:
                                    ReadOnlyEditableTextContextMenu.builder(
                                  selectedTextProvider: () =>
                                      _selectedMessageText,
                                  includeIosTranslate: true,
                                ),
                                onOpen: (link) async {
                                  await handleFALink(context, link.url);
                                },
                                text: messageContent,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                                linkStyle: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFE09321),
                                  decoration: TextDecoration.none,
                                  decorationColor: Color(0xFFE09321),
                                ),
                                selectionControls: MaterialTextSelectionControls(),
                              ),
                            ),
                          ),
                        ),
                        if (widget.allowMarkUnread && widget.folder != 'sent')
                          buildMessageDetailActions(
                            messageActionsFadeBottomInset:
                                messageActionsFadeBottomInset,
                            onMarkUnread: _markAsUnread,
                            onReply: () {
                              final replyToUsername =
                                  widget.folder == 'sent'
                                  ? recipientUsername
                                  : senderUsername;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  settings: const AnalyticsRouteSettings(
                                    AppScreens.noteReply,
                                  ),
                                  builder: (context) => NoteReplyScreen(
                                    subject: subject,
                                    originalContent: messageContent,
                                    originalContentHtml:
                                        messageContentHtml.isNotEmpty
                                        ? messageContentHtml
                                        : null,
                                    username: replyToUsername.isNotEmpty
                                        ? replyToUsername
                                        : senderUsername,
                                    messageId: messageId ?? '',
                                    messageLink: widget.messageLink,
                                    imagePreviewMode: imagePreviewMode,
                                  ),
                                ),
                              ).then((result) {
                                if (result == true) {
                                  rootMessengerKey.currentState
                                      ?.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Reply sent successfully!',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
