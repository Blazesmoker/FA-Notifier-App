import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:FANotifier/features/notes/domain/note_message_repository.dart';
import 'package:FANotifier/features/notes/domain/notes_refresh_port.dart';
import 'package:FANotifier/app/navigation/app_navigation.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/notes/presentation/note_reply_screen.dart';
import 'package:FANotifier/features/notes/domain/note_image_preview_mode.dart';
import 'package:FANotifier/features/notes/domain/note_submission_preview_repository.dart';
import 'package:FANotifier/features/notes/presentation/note_body_with_previews.dart';
import 'package:FANotifier/features/notes/presentation/note_image_preview_settings_provider.dart';
import 'package:FANotifier/shared/navigation/fa_link_handler.dart';
import 'package:FANotifier/shared/utils/utils.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/translation/native_translate_launcher.dart';
import 'package:FANotifier/core/preferences/translator_settings_provider.dart';
import 'package:provider/provider.dart';

const double _messageActionsFadeCeilingAboveButtons = 0.0;
const double _messageActionsFadeTransitionStart = 0.0;
const double _messageActionsFadeBlackStop = 1.00;
const double _messageActionsFadePosition = 0.35;
const double _messageActionsFadeSmoothness = 1.0;
const int _messageActionsFadeSteps = 64;
const double _messageActionsFadeBottomOffset = 18.0;
const double _messageActionsButtonsBottomOffset = 8.0;
const double _messageActionsScrollClearance = 96.0;

List<double> get _messageActionsFadeStops => List<double>.generate(
      _messageActionsFadeSteps + 1,
      (index) => index / _messageActionsFadeSteps,
    );

List<Color> get _messageActionsFadeColors => List<Color>.generate(
      _messageActionsFadeSteps + 1,
      (index) => Color.fromARGB(
        (_messageActionsFadeAlpha(index / _messageActionsFadeSteps) * 255)
            .round(),
        0,
        0,
        0,
      ),
    );

double _messageActionsFadeAlpha(double stop) {
  final transitionStart =
      _messageActionsFadeTransitionStart.clamp(0.0, 0.99).toDouble();
  final blackStop = _messageActionsFadeBlackStop
      .clamp(transitionStart + 0.01, 1.0)
      .toDouble();
  if (stop <= transitionStart) return 0.0;
  if (stop >= blackStop) return 1.0;

  final progress =
      (stop - transitionStart) / (blackStop - transitionStart);
  final position =
      _messageActionsFadePosition.clamp(0.01, 0.99).toDouble();
  final smoothness =
      _messageActionsFadeSmoothness.clamp(0.0, 1.0).toDouble();
  final steepness = 14.0 - (smoothness * 12.0);
  final shiftedProgress = (progress * (1.0 - position)) /
      (position + (progress * (1.0 - (2.0 * position))));

  double sigmoid(double value) {
    return 1.0 /
        (1.0 + math.exp(-steepness * (value - 0.5)));
  }

  final minimum = sigmoid(0.0);
  final maximum = sigmoid(1.0);
  final normalizedAlpha =
      ((sigmoid(shiftedProgress) - minimum) / (maximum - minimum))
      .clamp(0.0, 1.0)
      .toDouble();
  final edgeSmoothedAlpha =
      normalizedAlpha * normalizedAlpha * (3.0 - (2.0 * normalizedAlpha));
  return (normalizedAlpha +
          ((edgeSmoothedAlpha - normalizedAlpha) * smoothness))
      .clamp(0.0, 1.0)
      .toDouble();
}

class MessageDetailScreen extends StatefulWidget {
  final String messageLink;
  final String folder;

  const MessageDetailScreen({
    Key? key,
    required this.messageLink,
    required this.folder,
  }) : super(key: key);

  @override
  _MessageDetailScreenState createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
  late final NoteMessageRepository _noteMessageRepository;
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
  String _selectedMessageText = '';

  @override
  void initState() {
    super.initState();
    _noteMessageRepository = context.read<NoteMessageRepositoryFactory>()();
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

  @override
  Widget build(BuildContext context) {
    final imagePreviewSettings =
        context.watch<NoteImagePreviewSettingsProvider>();
    final imagePreviewMode = imagePreviewSettings.loaded
        ? imagePreviewSettings.mode
        : NoteImagePreviewMode.off;
    final hasImagePreviewLinks =
        imagePreviewMode != NoteImagePreviewMode.off &&
            noteBodyContainsSubmissionLinks(
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
        bottomSafeInset + _messageActionsFadeBottomOffset;
    final messageActionsButtonsBottomInset =
        bottomSafeInset + _messageActionsButtonsBottomOffset;
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
        canPop: true,
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
                      icon: const Icon(Icons.more_vert),
                      onPressed: () async {
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

                        final selected = await showMenu<String>(
                          context: context,
                          position: position,
                          items: const [
                            PopupMenuItem<String>(
                              value: 'translate',
                              child: Text('Translate'),
                            ),
                          ],
                        );
                        if (selected == 'translate') {
                          await _openMessageTranslation();
                        }
                      },
                    );
                  },
                ),
              ],
            ),
            backgroundColor: Colors.black,
            body: isLoading
                ? const Center(
              child: PulsatingLoadingIndicator(
                size: 108.0,
                assetPath: 'assets/icons/fathemed.png',
              ),
            )
                : errorMessage.isNotEmpty
                ? Center(
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            )
                : Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                top: 16.0,
                right: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!isClassic)
                        GestureDetector(
                          onTap: () {
                            final link = widget.folder == 'sent' ? recipientLink : senderLink;
                            if (link.isNotEmpty) {
                              handleFALink(context, link);
                            }
                          },
                          child: Container(
                            width: 60,
                            height: 60,
                            color: Colors.transparent,
                            child: FaNetworkImage(
                              'https:$avatarUrl',
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              errorBuilder: (context, error, stackTrace) {
                                return Transform.scale(
                                  scale: 1.05,
                                  child: Image.asset(
                                    'assets/images/defaultpic.gif',
                                    fit: BoxFit.cover,
                                  ),
                                );
                              },
                            ),

                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      const SizedBox(width: 16),
                      Expanded(child:
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Sent by: ',
                                style: TextStyle(fontSize: 16, color: Colors.white),
                              ),
                              widget.folder == 'sent'
                                  ? Text(
                                      sender.isNotEmpty ? sender : 'Unknown sender',
                                      style: const TextStyle(fontSize: 16, color: Colors.white),
                                    )
                                  : InkWell(
                                      onTap: senderLink.isNotEmpty
                                          ? () => handleFALink(context, senderLink)
                                          : null,
                                      child: Text(
                                        sender.isNotEmpty ? sender : 'Unknown sender',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFFE09321),
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'To: ',
                                style: TextStyle(fontSize: 16, color: Colors.white),
                              ),
                              widget.folder == 'sent' && recipientLink.isNotEmpty
                                  ? InkWell(
                                      onTap: () => handleFALink(context, recipientLink),
                                      child: Text(
                                        recipient.isNotEmpty ? recipient : 'Unknown recipient',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFFE09321),
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      recipient.isNotEmpty ? recipient : 'Unknown recipient',
                                      style: const TextStyle(fontSize: 16, color: Colors.white),
                                    ),
                            ],
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Date: $sentDate',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ),

                        ],
                      ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, thickness: 1, color: Colors.white54),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.only(
                              bottom: widget.folder != 'sent'
                                  ? _messageActionsScrollClearance +
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
                                  onLinkTap: (url, _, __) {
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
                        if (widget.folder != 'sent')
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: SizedBox(
                              width: double.infinity,
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final totalHeight =
                                              constraints.maxHeight;
                                          final fadeHeight = math.max(
                                            0.0,
                                            totalHeight -
                                                messageActionsFadeBottomInset,
                                          );
                                          final fadeEnd = totalHeight <= 0
                                              ? 1.0
                                              : (fadeHeight / totalHeight)
                                                  .clamp(0.0, 1.0)
                                                  .toDouble();
                                          return DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  ..._messageActionsFadeColors,
                                                  Colors.black,
                                                ],
                                                stops: [
                                                  ..._messageActionsFadeStops
                                                      .map(
                                                    (stop) => stop * fadeEnd,
                                                  ),
                                                  1.0,
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: _messageActionsFadeCeilingAboveButtons,
                                      bottom: messageActionsFadeBottomInset,
                                    ),
                                    child: Transform.translate(
                                      offset: const Offset(
                                        0,
                                        _messageActionsFadeBottomOffset -
                                            _messageActionsButtonsBottomOffset,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          OutlinedButton(
                                            onPressed: _markAsUnread,
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  const Color(0xFFE09321),
                                              side: const BorderSide(
                                                color: Color(0xFFE09321),
                                              ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize.padded,
                                            ),
                                            child: const Text('Mark Unread'),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () {
                                              final replyToUsername =
                                                  widget.folder == 'sent'
                                                      ? recipientUsername
                                                      : senderUsername;
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      NoteReplyScreen(
                                                    subject: subject,
                                                    originalContent:
                                                        messageContent,
                                                    originalContentHtml:
                                                        messageContentHtml
                                                                .isNotEmpty
                                                            ? messageContentHtml
                                                            : null,
                                                    username: replyToUsername
                                                            .isNotEmpty
                                                        ? replyToUsername
                                                        : senderUsername,
                                                    messageId: messageId ?? '',
                                                    messageLink:
                                                        widget.messageLink,
                                                    imagePreviewMode:
                                                        imagePreviewMode,
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
                                                      backgroundColor:
                                                          Colors.green,
                                                    ),
                                                  );
                                                }
                                              });
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFE09321),
                                              tapTargetSize:
                                                  MaterialTapTargetSize.padded,
                                            ),
                                            child: const Text('Reply'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
