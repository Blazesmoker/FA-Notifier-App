import 'dart:async';
import 'package:flutter/material.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/features/journals/data/journal_url_builder.dart';
import 'package:FANotifier/features/journals/presentation/create_journal.dart';
import 'package:FANotifier/features/journals/presentation/editjournalcommentscreen.dart';
import 'package:FANotifier/features/journals/presentation/journal_reply_screen.dart';
import 'package:FANotifier/features/journals/presentation/openjournal_controller.dart';
import 'package:FANotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:FANotifier/features/journals/presentation/openjournal_comments.dart';
import 'package:FANotifier/features/journals/domain/journal_deletion_result.dart';
import 'package:FANotifier/features/journals/domain/journal_load_failure.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:FANotifier/shared/utils/fa_link_handler.dart';
import 'package:FANotifier/shared/utils/utils.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/utils/comment_composer_lines.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:FANotifier/features/settings/data/translator_settings_provider.dart';
import 'package:FANotifier/shared/translation/ios_scroll_recovery.dart';
import 'package:FANotifier/shared/translation/native_translate_launcher.dart';
import 'package:FANotifier/shared/translation/translation_service.dart';
import 'package:FANotifier/shared/translation/translation_source_text_builder.dart';
import 'package:FANotifier/shared/platform/fa_share_service.dart';
import 'package:FANotifier/main.dart';
import 'package:provider/provider.dart';

import '../data/journal_link_parser.dart';

class OpenJournal extends StatefulWidget {
  final String uniqueNumber;
  final VoidCallback? onJournalMutated;

  const OpenJournal({
    required this.uniqueNumber,
    this.onJournalMutated,
    Key? key,
  }) : super(key: key);

  @override
  _OpenJournalState createState() => _OpenJournalState();
}

class _OpenJournalState extends State<OpenJournal>
    with RouteAware, WidgetsBindingObserver {
  late final OpenJournalController _controller;
  final TranslationService _translationService = TranslationService.instance;
  final TranslationSourceTextBuilder _translationSourceTextBuilder =
      TranslationSourceTextBuilder(TranslationService.instance);
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  bool _commentComposerFocusRequestedByUser = false;
  bool _blockRestoredCommentComposerFocus = true;
  final ValueNotifier<bool> _showScrollToTopNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isSendingInlineComment =
      ValueNotifier<bool>(false);
  final ValueNotifier<double> _keyboardInset = ValueNotifier<double>(0);
  final ValueNotifier<bool> _isCommentComposerExpanded =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> _commentDraftHasText = ValueNotifier<bool>(false);
  final ValueNotifier<int> _commentDraftCollapsedLines = ValueNotifier<int>(1);

  String? get profileImageUrl => _controller.profileImageUrl;
  String? get submissionTitle => _controller.submissionTitle;
  String? get submissionDescription => _controller.submissionDescription;
  int get commentsCount => _controller.commentsCount;
  List<Map<String, dynamic>> get comments => _controller.comments;
  String? get authorDisplayName => _controller.authorDisplayName;
  String? get authorUserName => _controller.authorUserName;
  String? get authorSymbol => _controller.authorSymbol;
  String? get authorUserTitle => _controller.authorUserTitle;
  bool get isJournalClassic => _controller.isJournalClassic;
  String? get fullViewImageUrl => _controller.fullViewImageUrl;
  String? get fileLink => _controller.fileLink;
  bool get isLoading => _controller.isLoading;
  bool get isOwner => _controller.isOwner;
  String? get category => _controller.category;
  String? get type => _controller.type;
  String? get species => _controller.species;
  String? get gender => _controller.gender;
  List<String> get keywords => _controller.keywords;

  bool _isDeleting = false;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey<SelectionAreaState> _titleSelectionKey = GlobalKey();
  final GlobalKey<SelectionAreaState> _journalBodySelectionKey = GlobalKey();
  final Map<Object, GlobalKey<SelectionAreaState>> _commentSelectionKeys =
      <Object, GlobalKey<SelectionAreaState>>{};
  final Map<Object, String> _commentSelectedTexts = <Object, String>{};
  String _titleSelectedText = '';
  String _journalBodySelectedText = '';
  int _iosScrollRecoveryKey = IosScrollRecovery.revision;
  int? _selectionClearPointerId;
  Offset? _selectionClearPointerDownPosition;
  DateTime? _selectionClearPointerDownTime;
  bool _selectionClearPointerMoved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _commentController.addListener(_onCommentDraftChanged);
    _commentFocusNode.addListener(_syncCommentComposerExpansion);
    _onCommentDraftChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateKeyboardInset();
    });
    _controller = OpenJournalController(journalId: widget.uniqueNumber);
    _controller.addListener(_handleControllerChanged);
    IosScrollRecovery.addListener(_handleIosScrollRecovery);
    // Only fetch the journal itself on open.
    // Extra "helper" fetches (user-page links, delete key) are done *on-demand*
    // when the user taps the relevant action, to avoid spammy requests.
    _fetchPostDetailsNew();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.unsubscribe(this);
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    IosScrollRecovery.removeListener(_handleIosScrollRecovery);
    _commentController.removeListener(_onCommentDraftChanged);
    _commentController.dispose();
    _commentFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _showScrollToTopNotifier.dispose();
    _isSendingInlineComment.dispose();
    _keyboardInset.dispose();
    _isCommentComposerExpanded.dispose();
    _commentDraftHasText.dispose();
    _commentDraftCollapsedLines.dispose();
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleIosScrollRecovery() {
    if (!mounted) return;
    final offset = IosScrollRecovery.currentOffset(_scrollController);
    setState(() {
      _iosScrollRecoveryKey = IosScrollRecovery.revision;
    });
    IosScrollRecovery.restoreOffset(_scrollController, offset);
  }

  @override
  void didPushNext() {
    _dismissCommentComposerFocus();
  }

  @override
  void didPopNext() {
    _armCommentComposerFocusGuard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_commentFocusNode.hasFocus) return;
      _commentFocusNode.unfocus();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.offset > 350;
    if (shouldShow == _showScrollToTopNotifier.value) return;
    _showScrollToTopNotifier.value = shouldShow;
  }

  Object _commentSelectionId(Map<String, dynamic> comment, int index) {
    return comment['commentId']?.toString() ?? 'comment_$index';
  }

  GlobalKey<SelectionAreaState> _commentSelectionKeyFor(Object selectionId) {
    return _commentSelectionKeys.putIfAbsent(
      selectionId,
      () => GlobalKey<SelectionAreaState>(),
    );
  }

  String _selectedCommentTextFor(Object selectionId) {
    return _commentSelectedTexts[selectionId] ?? '';
  }

  void _updateTitleSelectedText(SelectedContent? content) {
    _titleSelectedText = content?.plainText ?? '';
  }

  void _updateJournalBodySelectedText(SelectedContent? content) {
    _journalBodySelectedText = content?.plainText ?? '';
  }

  void _updateCommentSelectedText(
    Object selectionId,
    SelectedContent? content,
  ) {
    final text = content?.plainText ?? '';
    if (text.isEmpty) {
      _commentSelectedTexts.remove(selectionId);
      return;
    }
    _commentSelectedTexts[selectionId] = text;
  }

  bool _shouldOfferJournalTranslation(
    TranslatorSettingsProvider settings, {
    VoidCallback? onLanguageDetectionUpdated,
  }) {
    return _translationService.shouldOfferTranslation(
      _translationSourceTextBuilder.content(
        title: submissionTitle,
        descriptionHtml: submissionDescription,
      ),
      settings,
      onLanguageDetectionUpdated: onLanguageDetectionUpdated,
    );
  }

  bool _shouldOfferCommentTranslation(
    Map<String, dynamic> comment,
    TranslatorSettingsProvider settings, {
    VoidCallback? onLanguageDetectionUpdated,
  }) {
    if (!_translationSourceTextBuilder.isCommentAvailable(comment)) {
      return false;
    }
    return _translationService.shouldOfferTranslation(
      _translationSourceTextBuilder.comment(comment),
      settings,
      onLanguageDetectionUpdated: onLanguageDetectionUpdated,
    );
  }

  Future<void> _openJournalTranslation(
    TranslatorSettingsProvider settings,
  ) async {
    await NativeTranslateLauncher.open(
      _translationSourceTextBuilder.content(
        title: submissionTitle,
        descriptionHtml: submissionDescription,
      ),
      targetLanguageCode: settings.targetLanguageCode,
    );
  }

  Future<void> _openCommentTranslation(
    Map<String, dynamic> comment,
    TranslatorSettingsProvider settings,
  ) async {
    await NativeTranslateLauncher.open(
      _translationSourceTextBuilder.comment(comment),
      targetLanguageCode: settings.targetLanguageCode,
    );
  }

  void _handleTranslationLanguageDetected() {
    if (!mounted) return;
    setState(() {});
  }

  void _clearSelectionArea(GlobalKey<SelectionAreaState> key) {
    final state = key.currentState;
    if (state == null) return;
    state.selectableRegion.clearSelection();
    state.selectableRegion.hideToolbar();
  }

  void _clearAllTextSelections() {
    _clearSelectionArea(_titleSelectionKey);
    _clearSelectionArea(_journalBodySelectionKey);
    for (final key in _commentSelectionKeys.values) {
      _clearSelectionArea(key);
    }
  }

  void _handleSelectionClearPointerDown(PointerDownEvent event) {
    _selectionClearPointerId = event.pointer;
    _selectionClearPointerDownPosition = event.position;
    _selectionClearPointerDownTime = DateTime.now();
    _selectionClearPointerMoved = false;
  }

  void _handleSelectionClearPointerMove(PointerMoveEvent event) {
    if (_selectionClearPointerId != event.pointer ||
        _selectionClearPointerDownPosition == null) {
      return;
    }
    if ((event.position - _selectionClearPointerDownPosition!).distance > 10) {
      _selectionClearPointerMoved = true;
    }
  }

  void _handleSelectionClearPointerUp(PointerUpEvent event) {
    if (_selectionClearPointerId != event.pointer) return;
    final downTime = _selectionClearPointerDownTime;
    final isQuickTap = downTime != null &&
        DateTime.now().difference(downTime) <=
            const Duration(milliseconds: 250);
    if (!_selectionClearPointerMoved && isQuickTap) {
      _clearAllTextSelections();
    }
    _resetSelectionClearPointer();
  }

  void _handleSelectionClearPointerCancel(PointerCancelEvent event) {
    if (_selectionClearPointerId != event.pointer) return;
    _resetSelectionClearPointer();
  }

  void _resetSelectionClearPointer() {
    _selectionClearPointerId = null;
    _selectionClearPointerDownPosition = null;
    _selectionClearPointerDownTime = null;
    _selectionClearPointerMoved = false;
  }

  @override
  void didChangeMetrics() {
    _updateKeyboardInset();
  }

  void _updateKeyboardInset() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;

    final view = views.first;
    final previousInset = _keyboardInset.value;
    final inset = view.viewInsets.bottom / view.devicePixelRatio;

    if ((inset - previousInset).abs() > 0.5) {
      _keyboardInset.value = inset;

      final keyboardJustClosed = previousInset > 0 && inset <= 0.5;
      if (keyboardJustClosed && _commentFocusNode.hasFocus) {
        _commentFocusNode.unfocus();
      }
    }
  }

  Future<void> _fetchPostDetailsNew() async {
    try {
      final loadResult = await _controller.load();

      if (loadResult.isUnavailable) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This journal does not exist or has been deleted'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );

          Future.delayed(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            Navigator.of(context).pop();
          });
        });
        return;
      }
    } catch (e) {
      debugPrint('Failed to fetch journal details: $e');

      if (!mounted) return;

      final message = journalLoadFailureMessage(e);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );

        Future.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          Navigator.of(context).pop();
        });
      });
    }
  }

  Future<void> _confirmAndDeleteJournal() async {
    if (_isDeleting) return;

    final titleForDialog =
        (submissionTitle == null || submissionTitle!.trim().isEmpty)
            ? '#${widget.uniqueNumber}'
            : submissionTitle!.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm deletion'),
        content:
            Text('Are you sure you want to delete journal "$titleForDialog"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      final result = await _controller.deleteJournal();
      if (result.status == JournalDeletionStatus.invalidDeleteLink) {
        showAppSnackBar(context,
            "Safe delete failed: couldn't confirm delete link for this journal.",
            backgroundColor: Colors.red);
        return;
      }

      if (result.status == JournalDeletionStatus.missingCookies) {
        showAppSnackBar(context, 'Please log in to perform this action.',
            backgroundColor: Colors.red);
        return;
      }

      if (result.status == JournalDeletionStatus.httpFailure) {
        if (!mounted) return;
        showAppSnackBar(context, 'Delete failed (HTTP ${result.statusCode}).',
            backgroundColor: Colors.red);
        return;
      }

      if (!mounted) return;

      if (result.status == JournalDeletionStatus.deleted) {
        widget.onJournalMutated?.call();
        showAppSnackBar(context, 'Journal "$titleForDialog" deleted.',
            backgroundColor: Colors.green);
        Navigator.of(context).pop(true);
      } else {
        showAppSnackBar(
          context,
          'Delete request completed, but the journal still exists.',
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Error while deleting: $e',
          backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> hideComment(String hideLink, String commentId) async {
    final shouldHide = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmation"),
          content: const Text("Are you sure you want to hide this comment?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Yes"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
    if (shouldHide == true) {
      try {
        final statusCode = await _controller.updateCommentVisibility(hideLink);
        if (statusCode == null) return;
        if (statusCode == 200) {
          showAppSnackBar(context, "Comment successfully hidden!",
              backgroundColor: Colors.green);
          await _fetchPostDetailsNew();
        } else {
          debugPrint('Failed to hide comment. Status code: $statusCode');
        }
      } catch (e) {
        debugPrint('Error hiding comment: $e');
      }
    }
  }

  Future<void> _unhideComment(String unhideLink, String commentId) async {
    final shouldUnhide = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmation"),
          content: const Text("Are you sure you want to unhide this comment?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Yes"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
    if (shouldUnhide == true) {
      try {
        final statusCode =
            await _controller.updateCommentVisibility(unhideLink);
        if (statusCode == null) return;
        if (statusCode == 200) {
          showAppSnackBar(context, "Comment successfully un-hidden!",
              backgroundColor: Colors.green);
          await _fetchPostDetailsNew();
        } else {
          debugPrint('Failed to unhide comment. Status code: $statusCode');
        }
      } catch (e) {
        debugPrint('Error un-hiding comment: $e');
      }
    }
  }

  void _sharePost() {
    final postUrl = buildFaJournalUrl(widget.uniqueNumber);
    final shareContent = '$postUrl';
    const FaShareService().shareText(
      text: shareContent,
      subject: submissionTitle ?? 'Fur Affinity Post',
    );
  }

  void _syncCommentComposerExpansion() {
    final shouldExpand = _commentFocusNode.hasFocus;
    if (shouldExpand &&
        _blockRestoredCommentComposerFocus &&
        !_commentComposerFocusRequestedByUser) {
      _dismissCommentComposerFocus();
      return;
    }
    if (shouldExpand != _isCommentComposerExpanded.value) {
      _isCommentComposerExpanded.value = shouldExpand;
    }
    if (shouldExpand) {
      _commentComposerFocusRequestedByUser = false;
      _blockRestoredCommentComposerFocus = false;
    } else {
      _commentComposerFocusRequestedByUser = false;
      _blockRestoredCommentComposerFocus = true;
    }
  }

  void _armCommentComposerFocusGuard() {
    _commentComposerFocusRequestedByUser = false;
    _blockRestoredCommentComposerFocus = true;
  }

  void _allowCommentComposerFocusFromUser() {
    _commentComposerFocusRequestedByUser = true;
    _blockRestoredCommentComposerFocus = false;
  }

  void _handleCommentComposerPointerDown(PointerDownEvent event) {
    _allowCommentComposerFocusFromUser();
  }

  void _dismissCommentComposerFocus() {
    _armCommentComposerFocusGuard();
    if (_commentFocusNode.hasFocus) {
      _commentFocusNode.unfocus();
    }
  }

  void _onCommentDraftChanged() {
    final bool hasText = _commentController.text.trim().isNotEmpty;
    if (hasText != _commentDraftHasText.value) {
      _commentDraftHasText.value = hasText;
    }

    final int collapsedLines = collapsedComposerLines(_commentController.text);
    if (collapsedLines != _commentDraftCollapsedLines.value) {
      _commentDraftCollapsedLines.value = collapsedLines;
    }
  }

  Future<void> _sendInlineComment() async {
    final commentText = _commentController.text.trim();
    if (commentText.isEmpty || _isSendingInlineComment.value) return;
    _isSendingInlineComment.value = true;

    try {
      final success = await _controller.submitComment(commentText);

      if (!mounted) return;

      if (success) {
        _controller.addOptimisticComment(commentText, DateTime.now());
        _commentController.clear();
        _commentFocusNode.unfocus();
        await _fetchPostDetailsNew();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment posted!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error posting comment. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        _isSendingInlineComment.value = false;
      }
    }
  }

  Widget _buildComposerSendButton({
    required bool canSend,
    required bool isSending,
    bool compact = false,
  }) {
    final buttonSize = compact ? 30.0 : 40.0;

    if (isSending) {
      return SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return IconButton(
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: buttonSize,
        height: buttonSize,
      ),
      visualDensity: VisualDensity.compact,
      icon: Icon(
        Icons.send,
        color: canSend ? const Color(0xFFE09321) : Colors.white54,
      ),
      onPressed: canSend ? _sendInlineComment : null,
    );
  }

  Future<bool> _confirmCloseJournalIfNeeded() async {
    if (_commentController.text.trim().isEmpty) {
      return true;
    }

    return ConfirmCloseDialog.show(
      context,
      title: 'Discard draft?',
      message: 'Are you sure you want to close this journal?',
    );
  }

  Future<void> _closeJournal() async {
    final canClose = await _confirmCloseJournalIfNeeded();
    if (!canClose || !mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final translatorSettings = context.watch<TranslatorSettingsProvider>();
    final double viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
    return ValueListenableBuilder<bool>(
      valueListenable: _commentDraftHasText,
      builder: (context, hasDraft, child) {
        return PopScope(
          canPop: !hasDraft,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              _closeJournal();
            }
          },
          child: child!,
        );
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: const Text("Journal"),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _closeJournal,
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              position: PopupMenuPosition.under,
              offset: const Offset(0, 8),
              onOpened: _dismissCommentComposerFocus,
              onSelected: (value) {
                switch (value) {
                  case 'share':
                    _sharePost();
                    break;
                  case 'edit':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CreateJournalScreen(
                          uniqueNumber: widget.uniqueNumber,
                          onJournalSubmitted: widget.onJournalMutated,
                        ),
                      ),
                    ).then((_) => _fetchPostDetailsNew());
                    break;
                  case 'delete':
                    if (!isOwner) {
                      showAppSnackBar(context,
                          'You do not have permission to delete this journal.',
                          backgroundColor: Colors.red);
                      break;
                    }
                    unawaited(_confirmAndDeleteJournal());
                    break;
                  case 'translate':
                    unawaited(_openJournalTranslation(translatorSettings));
                    break;
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'share',
                  child: Text('Share'),
                ),
                if (isOwner)
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                if (isOwner)
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                const PopupMenuItem<String>(
                  value: 'translate',
                  child: Text('Translate'),
                ),
              ],
            ),
          ],
        ),
        body: isLoading
            ? const Center(
                child: PulsatingLoadingIndicator(
                    size: 78.0, assetPath: 'assets/icons/fathemed.png'))
            : Stack(
                children: [
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _handleSelectionClearPointerDown,
                    onPointerMove: _handleSelectionClearPointerMove,
                    onPointerUp: _handleSelectionClearPointerUp,
                    onPointerCancel: _handleSelectionClearPointerCancel,
                    child: GestureDetector(
                      behavior: HitTestBehavior.deferToChild,
                      onTap: () {
                        FocusScope.of(context).unfocus();
                      },
                      child: RefreshIndicator(
                        color: const Color(0xFFE09321),
                        backgroundColor: Colors.black,
                        onRefresh: _fetchPostDetailsNew,
                        child: CustomScrollView(
                          key: ValueKey<int>(_iosScrollRecoveryKey),
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4.0, horizontal: 8.0),
                                child: Card(
                                  color: const Color(0xFF151515),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (profileImageUrl != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 8.0, top: 4.0),
                                                child: GestureDetector(
                                                  onTap: () {
                                                    if (authorUserName !=
                                                            null &&
                                                        authorUserName!
                                                            .isNotEmpty) {
                                                      Navigator.push(
                                                        context,
                                                        UserProfileScreen.route(
                                                          nickname:
                                                              authorUserName!,
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  child: FaNetworkImage(
                                                    profileImageUrl!,
                                                    width: 46,
                                                    height: 46,
                                                    fit: BoxFit.cover,
                                                    loadingBuilder: (context,
                                                        child,
                                                        loadingProgress) {
                                                      if (loadingProgress ==
                                                          null) {
                                                        return child;
                                                      }
                                                      return Image.asset(
                                                        'assets/images/defaultpic.gif',
                                                        width: 46,
                                                        height: 46,
                                                        fit: BoxFit.cover,
                                                      );
                                                    },
                                                    errorBuilder: (context,
                                                        error, stackTrace) {
                                                      return Image.asset(
                                                        'assets/images/defaultpic.gif',
                                                        width: 46,
                                                        height: 46,
                                                        fit: BoxFit.cover,
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    authorDisplayName ??
                                                        authorUserName ??
                                                        'Anonymous',
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  if (authorUserName != null &&
                                                      authorUserName!
                                                          .isNotEmpty)
                                                    Text(
                                                      '${(authorSymbol == null || authorSymbol!.isEmpty) ? '@' : authorSymbol!}${authorUserName!}',
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Color(
                                                              0xFFE09321)),
                                                    ),
                                                  if (!isJournalClassic &&
                                                      (authorUserTitle ?? '')
                                                          .isNotEmpty)
                                                    Text(
                                                      authorUserTitle!,
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey.shade400),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        Divider(
                                            color: Colors.grey.shade900,
                                            thickness: 1.5,
                                            height: 24),
                                        SelectionArea(
                                          key: _titleSelectionKey,
                                          onSelectionChanged:
                                              _updateTitleSelectedText,
                                          contextMenuBuilder:
                                              ReadOnlySelectionContextMenu
                                                  .builder(
                                            selectedTextProvider: () =>
                                                _titleSelectedText,
                                            includeIosTranslate: true,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                submissionTitle ?? '',
                                                style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                  'Posted on: ${_controller.formattedPublicationTime ?? ''}'),
                                            ],
                                          ),
                                        ),
                                        Divider(
                                            color: Colors.grey.shade900,
                                            thickness: 1.5,
                                            height: 24),
                                        Theme(
                                          data: Theme.of(context).copyWith(
                                            textSelectionTheme:
                                                TextSelectionThemeData(
                                              selectionColor:
                                                  const Color(0xFFE09321)
                                                      .withValues(alpha: 0.4),
                                              selectionHandleColor:
                                                  const Color(0xFFE09321),
                                            ),
                                          ),
                                          child: SelectionArea(
                                            key: _journalBodySelectionKey,
                                            onSelectionChanged:
                                                _updateJournalBodySelectedText,
                                            contextMenuBuilder:
                                                ReadOnlySelectionContextMenu
                                                    .builder(
                                              selectedTextProvider: () =>
                                                  _journalBodySelectedText,
                                              includeIosTranslate: true,
                                            ),
                                            child: html_pkg.Html(
                                              data: submissionDescription ?? '',
                                              style: {
                                                "body": html_pkg.Style(
                                                  textAlign: TextAlign.left,
                                                  fontSize:
                                                      html_pkg.FontSize(16),
                                                  padding: html_pkg
                                                      .HtmlPaddings.zero,
                                                  margin: html_pkg.Margins.zero,
                                                  backgroundColor:
                                                      Colors.transparent,
                                                ),
                                                "a": html_pkg.Style(
                                                  textDecoration:
                                                      TextDecoration.none,
                                                  color:
                                                      const Color(0xFFE09321),
                                                ),
                                                "hr": html_pkg.Style(
                                                  padding: html_pkg.HtmlPaddings
                                                      .symmetric(vertical: 8),
                                                  margin: html_pkg.Margins
                                                      .symmetric(vertical: 8),
                                                  height: html_pkg.Height(1),
                                                ),
                                                ".bbcode_center":
                                                    html_pkg.Style(
                                                  textAlign: TextAlign.center,
                                                  display:
                                                      html_pkg.Display.block,
                                                ),
                                                ".bbcode_right": html_pkg.Style(
                                                  textAlign: TextAlign.right,
                                                  display:
                                                      html_pkg.Display.block,
                                                ),
                                                ".bbcode_left": html_pkg.Style(
                                                  textAlign: TextAlign.left,
                                                  display:
                                                      html_pkg.Display.block,
                                                ),
                                              },
                                              onLinkTap: (url, _, __) =>
                                                  handleFALink(context, url!,
                                                      htmlSource:
                                                          submissionDescription,
                                                      getFullUrl:
                                                          _controller.getFullLink),
                                              extensions: [
                                                html_pkg.TagExtension(
                                                  tagsToExtend: {"i"},
                                                  builder:
                                                      (html_pkg.ExtensionContext
                                                          context) {
                                                    final classAttr = context
                                                        .attributes['class'];
                                                    if (classAttr ==
                                                        'bbcode bbcode_i') {
                                                      return Text(
                                                        context
                                                                .styledElement
                                                                ?.element
                                                                ?.text ??
                                                            "",
                                                        style: const TextStyle(
                                                          fontStyle:
                                                              FontStyle.italic,
                                                          color: Colors.white,
                                                        ),
                                                      );
                                                    }
                                                    switch (classAttr) {
                                                      case 'smilie tongue':
                                                        return Image.asset(
                                                            'assets/emojis/tongue.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie evil':
                                                        return Image.asset(
                                                            'assets/emojis/evil.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie lmao':
                                                        return Image.asset(
                                                            'assets/emojis/lmao.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie gift':
                                                        return Image.asset(
                                                            'assets/emojis/gift.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie derp':
                                                        return Image.asset(
                                                            'assets/emojis/derp.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie teeth':
                                                        return Image.asset(
                                                            'assets/emojis/teeth.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie cool':
                                                        return Image.asset(
                                                            'assets/emojis/cool.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie huh':
                                                        return Image.asset(
                                                            'assets/emojis/huh.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie cd':
                                                        return Image.asset(
                                                            'assets/emojis/cd.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie coffee':
                                                        return Image.asset(
                                                            'assets/emojis/coffee.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie sarcastic':
                                                        return Image.asset(
                                                            'assets/emojis/sarcastic.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie veryhappy':
                                                        return Image.asset(
                                                            'assets/emojis/veryhappy.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie wink':
                                                        return Image.asset(
                                                            'assets/emojis/wink.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie whatever':
                                                        return Image.asset(
                                                            'assets/emojis/whatever.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie crying':
                                                        return Image.asset(
                                                            'assets/emojis/crying.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie love':
                                                        return Image.asset(
                                                            'assets/emojis/love.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie serious':
                                                        return Image.asset(
                                                            'assets/emojis/serious.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie yelling':
                                                        return Image.asset(
                                                            'assets/emojis/yelling.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie oooh':
                                                        return Image.asset(
                                                            'assets/emojis/oooh.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie angel':
                                                        return Image.asset(
                                                            'assets/emojis/angel.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie dunno':
                                                        return Image.asset(
                                                            'assets/emojis/dunno.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie nerd':
                                                        return Image.asset(
                                                            'assets/emojis/nerd.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie sad':
                                                        return Image.asset(
                                                            'assets/emojis/sad.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie zipped':
                                                        return Image.asset(
                                                            'assets/emojis/zipped.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie smile':
                                                        return Image.asset(
                                                            'assets/emojis/smile.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie badhairday':
                                                        return Image.asset(
                                                            'assets/emojis/badhairday.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie embarrassed':
                                                        return Image.asset(
                                                            'assets/emojis/embarrassed.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie note':
                                                        return Image.asset(
                                                            'assets/emojis/note.png',
                                                            width: 20,
                                                            height: 20);
                                                      case 'smilie sleepy':
                                                        return Image.asset(
                                                            'assets/emojis/sleepy.png',
                                                            width: 20,
                                                            height: 20);
                                                      default:
                                                        return const SizedBox
                                                            .shrink();
                                                    }
                                                  },
                                                ),
                                                html_pkg.TagExtension(
                                                  tagsToExtend: {"img"},
                                                  builder:
                                                      (html_pkg.ExtensionContext
                                                          context) {
                                                    final src = context
                                                        .attributes['src'];
                                                    if (src == null)
                                                      return const SizedBox
                                                          .shrink();
                                                    final resolvedUrl =
                                                        src.startsWith('//')
                                                            ? 'https:$src'
                                                            : src;
                                                    // Check if this image is a profile emoji.
                                                    if (resolvedUrl.contains(
                                                            "a.furaffinity.net") &&
                                                        resolvedUrl
                                                            .endsWith(".gif")) {
                                                      return FaNetworkImage(
                                                        resolvedUrl,
                                                        width:
                                                            50, // profile emoji size.
                                                        height: 50,
                                                        fit: BoxFit.contain,
                                                        loadingBuilder: (context,
                                                            child,
                                                            loadingProgress) {
                                                          if (loadingProgress ==
                                                              null) {
                                                            return child;
                                                          }
                                                          return const SizedBox(
                                                            width: 50,
                                                            height: 50,
                                                            child:
                                                                CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2),
                                                          );
                                                        },
                                                        errorBuilder: (context,
                                                            error, stackTrace) {
                                                          return Image.asset(
                                                            'assets/images/defaultpic.gif',
                                                            width: 50,
                                                            height: 50,
                                                            fit: BoxFit.contain,
                                                          );
                                                        },
                                                      );
                                                    }

                                                    return FaNetworkImage(
                                                      resolvedUrl,
                                                      width: 50,
                                                      height: 50,
                                                      fit: BoxFit.cover,
                                                      loadingBuilder: (context,
                                                          child,
                                                          loadingProgress) {
                                                        if (loadingProgress ==
                                                            null) {
                                                          return child;
                                                        }
                                                        return const SizedBox(
                                                          width: 50,
                                                          height: 50,
                                                          child:
                                                              CircularProgressIndicator(),
                                                        );
                                                      },
                                                      errorBuilder: (context,
                                                          error, stackTrace) {
                                                        return Image.asset(
                                                          'assets/images/defaultpic.gif',
                                                          width: 50,
                                                          height: 50,
                                                          fit: BoxFit.cover,
                                                        );
                                                      },
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: const Divider(
                                height: 3.0,
                                color: Color(0xFF111111),
                                thickness: 3.0,
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12.0, vertical: 12.0),
                                child: Center(
                                  child: Text(
                                    commentsCount > 0
                                        ? '$commentsCount Comments'
                                        : 'No Comments',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: const Divider(
                                height: 3.0,
                                color: Color(0xFF111111),
                                thickness: 3.0,
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 8),
                            ),
                            SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final comment = comments[index];
                                    final selectionId =
                                        _commentSelectionId(comment, index);
                                    final previousComment =
                                        index > 0 ? comments[index - 1] : null;
                                    final nextComment =
                                        index + 1 < comments.length
                                            ? comments[index + 1]
                                            : null;
                                    final previousNestingLevel =
                                        previousComment == null
                                            ? 0
                                            : ((100.0 -
                                                        (previousComment[
                                                                    'width'] ??
                                                                100)
                                                            .toDouble()) /
                                                    3.0)
                                                .round()
                                                .clamp(0, 4)
                                                .toInt();
                                    final nextNestingLevel = nextComment == null
                                        ? 0
                                        : ((100.0 -
                                                    (nextComment['width'] ??
                                                            100)
                                                        .toDouble()) /
                                                3.0)
                                            .round()
                                            .clamp(0, 4)
                                            .toInt();
                                    return CommentWidget(
                                      key: ValueKey(
                                          comment['commentId'] ?? index),
                                      comment: comment,
                                      previousNestingLevel:
                                          previousNestingLevel,
                                      nextNestingLevel: nextNestingLevel,
                                      onHide: (comment['hideLink'] != null)
                                          ? () => hideComment(
                                              comment['hideLink'],
                                              comment['commentId'] ?? '')
                                          : null,
                                      onEdit: (comment['editLink'] != null)
                                          ? () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      EditJournalCommentScreen(
                                                    comment: comment,
                                                    editLink:
                                                        comment['editLink'],
                                                    onUpdateComment: () async {
                                                      await _fetchPostDetailsNew();
                                                    },
                                                  ),
                                                ),
                                              );
                                            }
                                          : null,
                                      onReply: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                JournalReplyScreen(
                                              submissionId: widget.uniqueNumber,
                                              commentId:
                                                  comment['commentId'] ?? '',
                                              onSendReply: (replyText) {},
                                              username: comment['username'] ??
                                                  'Anonymous',
                                              profileImage:
                                                  comment['profileImage'] ?? '',
                                              commentHtml:
                                                  comment['commentHtml'],
                                              commentText: comment['text'],
                                            ),
                                          ),
                                        ).then((result) {
                                          if (result == true) {
                                            _fetchPostDetailsNew();
                                          }
                                        });
                                      },
                                      onUnhide: (comment['deleted'] == true &&
                                              comment['unhideLink'] != null)
                                          ? () => _unhideComment(
                                              comment['unhideLink'],
                                              comment['commentId'] ?? '')
                                          : null,
                                      handleLink: (url) async {
                                        final commentHtml =
                                            comment['commentHtml'] ?? '';
                                        await handleFALink(
                                          context,
                                          url,
                                          htmlSource: commentHtml,
                                          getFullUrl:
                                              _controller.getFullLink,
                                        );
                                      },
                                      selectionAreaKey:
                                          _commentSelectionKeyFor(selectionId),
                                      onSelectionChanged: (content) =>
                                          _updateCommentSelectedText(
                                              selectionId, content),
                                      contextMenuBuilder:
                                          ReadOnlySelectionContextMenu.builder(
                                        selectedTextProvider: () =>
                                            _selectedCommentTextFor(
                                                selectionId),
                                        includeIosTranslate: true,
                                      ),
                                      showTranslateButton:
                                          _shouldOfferCommentTranslation(
                                        comment,
                                        translatorSettings,
                                        onLanguageDetectionUpdated:
                                            _handleTranslationLanguageDetected,
                                      ),
                                      onTranslateToggle: () =>
                                          _openCommentTranslation(
                                        comment,
                                        translatorSettings,
                                      ),
                                    );
                                  },
                                  childCount: comments.length,
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: ListenableBuilder(
                                listenable: Listenable.merge([
                                  _isCommentComposerExpanded,
                                  _commentDraftCollapsedLines,
                                ]),
                                builder: (context, _) {
                                  final isExpanded =
                                      _isCommentComposerExpanded.value;
                                  final collapsedPreviewLines =
                                      _commentDraftCollapsedLines.value;
                                  final composerSpacerHeight = isExpanded
                                      ? 198.0
                                      : (72.0 +
                                          ((collapsedPreviewLines - 1) * 24.0));
                                  return SizedBox(height: composerSpacerHeight);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _isCommentComposerExpanded,
                      builder: (context, isExpanded, _) {
                        if (!isExpanded) {
                          return const SizedBox.shrink();
                        }
                        return GestureDetector(
                          onTap: () => FocusScope.of(context).unfocus(),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.24),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: isLoading
            ? null
            : RepaintBoundary(
                child: Container(
                  color: Colors.black,
                  child: SafeArea(
                    bottom: true,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        _keyboardInset,
                        _isCommentComposerExpanded,
                      ]),
                      builder: (context, _) {
                        final keyboardInset = _keyboardInset.value;
                        return Padding(
                          padding: EdgeInsets.only(
                            left: 8,
                            right: 8,
                            bottom: keyboardInset > 0
                                ? (keyboardInset - viewPaddingBottom + 8)
                                    .clamp(0.0, double.infinity)
                                : 0.0,
                            top: 8,
                          ),
                          child: ListenableBuilder(
                            listenable: Listenable.merge([
                              _isCommentComposerExpanded,
                              _commentDraftCollapsedLines,
                              _commentDraftHasText,
                              _showScrollToTopNotifier,
                              _isSendingInlineComment,
                            ]),
                            builder: (context, _) {
                              final isExpanded =
                                  _isCommentComposerExpanded.value;
                              final collapsedLines =
                                  _commentDraftCollapsedLines.value;
                              final hasText = _commentDraftHasText.value;
                              final isSending = _isSendingInlineComment.value;
                              final canSend = !isSending && hasText;
                              final minLines = isExpanded ? 6 : collapsedLines;
                              final maxLines = isExpanded ? 6 : collapsedLines;
                              final isCollapsedSingleLine =
                                  !isExpanded && collapsedLines == 1;

                              const compactSingleLineVerticalPadding = 8.0;
                              final topPadding = isExpanded
                                  ? 12.0
                                  : (isCollapsedSingleLine
                                      ? compactSingleLineVerticalPadding
                                      : 8.0);
                              final bottomPadding = isExpanded
                                  ? 8.0
                                  : (isCollapsedSingleLine
                                      ? compactSingleLineVerticalPadding
                                      : 8.0);

                              return Row(
                                crossAxisAlignment: isCollapsedSingleLine
                                    ? CrossAxisAlignment.center
                                    : CrossAxisAlignment.end,
                                children: [
                                  ClipRect(
                                    child: AnimatedSize(
                                      duration:
                                          const Duration(milliseconds: 210),
                                      curve: Curves.easeInOut,
                                      alignment: Alignment.centerLeft,
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable:
                                            _showScrollToTopNotifier,
                                        builder: (context, show, _) {
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (show && !isExpanded)
                                                SizedBox(
                                                  width: 36,
                                                  height: 36,
                                                  child: FloatingActionButton
                                                      .small(
                                                    heroTag:
                                                        'journal_scroll_top',
                                                    backgroundColor:
                                                        const Color(0xFFE09321),
                                                    elevation: 0,
                                                    onPressed: () {
                                                      _scrollController
                                                          .animateTo(
                                                        0,
                                                        duration:
                                                            const Duration(
                                                                milliseconds:
                                                                    300),
                                                        curve: Curves.easeOut,
                                                      );
                                                    },
                                                    child: const Icon(
                                                      Icons.arrow_upward,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ),
                                              if (show && !isExpanded)
                                                const SizedBox(width: 8),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        Listener(
                                          behavior: HitTestBehavior.translucent,
                                          onPointerDown:
                                              _handleCommentComposerPointerDown,
                                          child: TextField(
                                            controller: _commentController,
                                            focusNode: _commentFocusNode,
                                            style: const TextStyle(
                                                color: Colors.white),
                                            keyboardType:
                                                TextInputType.multiline,
                                            textInputAction:
                                                TextInputAction.newline,
                                            minLines: minLines,
                                            maxLines: maxLines,
                                            scrollPadding:
                                                const EdgeInsets.only(
                                                    bottom: 8),
                                            decoration: InputDecoration(
                                              hintText: 'Add a comment...',
                                              hintStyle: const TextStyle(
                                                  color: Colors.white54),
                                              contentPadding:
                                                  EdgeInsets.fromLTRB(
                                                12,
                                                topPadding,
                                                56,
                                                bottomPadding,
                                              ),
                                              filled: true,
                                              isDense: isCollapsedSingleLine,
                                              fillColor:
                                                  const Color(0xFF151515),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: BorderSide.none,
                                              ),
                                            ),
                                            contextMenuBuilder:
                                                BBCodeContextMenu.builder(
                                                    _commentController),
                                          ),
                                        ),
                                        if (isCollapsedSingleLine)
                                          Positioned.fill(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 4),
                                                child: _buildComposerSendButton(
                                                  canSend: canSend,
                                                  isSending: isSending,
                                                  compact: true,
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: _buildComposerSendButton(
                                              canSend: canSend,
                                              isSending: isSending,
                                            ),
                                          ),
                                        if (isExpanded && hasText && !isSending)
                                          Positioned(
                                            right: 4,
                                            bottom: 4,
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.clear,
                                                color: Colors.white54,
                                              ),
                                              onPressed: () {
                                                _commentController.clear();
                                              },
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String fixTruncatedLinks(String htmlContent) {
    return replaceTruncatedJournalLinks(htmlContent);
  }
}
