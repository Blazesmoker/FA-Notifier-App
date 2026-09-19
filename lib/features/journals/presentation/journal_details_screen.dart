import 'widgets/journal_body.dart';
import 'widgets/journal_author_header.dart';
import 'widgets/journal_delete_dialog.dart';
import 'widgets/journal_action_menu.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/features/journals/domain/journal_details_repository.dart';
import 'package:fanotifier/features/journals/presentation/create_journal_screen.dart';
import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/journals/presentation/edit_journal_comment_screen.dart';
import 'package:fanotifier/features/journals/presentation/journal_reply_screen.dart';
import 'package:fanotifier/features/journals/presentation/journal_details_controller.dart';
import 'package:fanotifier/features/comments/presentation/inline_comment_composer.dart';
import 'package:fanotifier/features/comments/presentation/threaded_comments.dart';
import 'package:fanotifier/features/comments/presentation/comment_settings_provider.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:fanotifier/features/journals/presentation/journal_comment_widget.dart';
import 'package:fanotifier/features/journals/domain/journal_deletion_result.dart';
import 'package:fanotifier/features/journals/domain/journal_load_failure.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';
import 'package:fanotifier/shared/utils/app_snack_bar.dart';
import 'package:fanotifier/shared/utils/comment_composer_lines.dart';
import 'package:fanotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:fanotifier/core/preferences/translator_settings_provider.dart';
import 'package:fanotifier/features/settings/domain/time_display_models.dart';
import 'package:fanotifier/features/settings/presentation/time_display_settings_provider.dart';
import 'package:fanotifier/shared/translation/ios_scroll_recovery.dart';
import 'package:fanotifier/shared/translation/native_translate_launcher.dart';
import 'package:fanotifier/shared/translation/translation_service.dart';
import 'package:fanotifier/shared/translation/translation_source_text_builder.dart';
import 'package:fanotifier/shared/platform/fa_share_service.dart';
import 'package:fanotifier/app/navigation/app_navigation.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/bbcode_context_menu.dart';

class JournalDetailsScreen extends StatefulWidget {
  final String journalId;
  final VoidCallback? onJournalMutated;
  final JournalDetailsRepository? repository;

  const JournalDetailsScreen({
    required this.journalId,
    this.onJournalMutated,
    this.repository,
    super.key,
  });

  @override
  State<JournalDetailsScreen> createState() => _JournalDetailsScreenState();
}

class _JournalDetailsScreenState extends State<JournalDetailsScreen>
    with RouteAware, WidgetsBindingObserver {
  late final JournalDetailsController _controller;
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
    _controller = JournalDetailsController(
      journalId: widget.journalId,
      repository: widget.repository ?? context.read<JournalDetailsRepository>(),
    );
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
        _dismissCommentComposerFocus();
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
            ? '#${widget.journalId}'
            : submissionTitle!.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => buildJournalDeleteDialog(ctx, titleForDialog: titleForDialog),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      final result = await _controller.deleteJournal();
      if (!mounted) return;
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
    if (!mounted) return;
    if (shouldHide == true) {
      try {
        final statusCode = await _controller.updateCommentVisibility(hideLink);
        if (!mounted) return;
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
    if (!mounted) return;
    if (shouldUnhide == true) {
      try {
        final statusCode =
            await _controller.updateCommentVisibility(unhideLink);
        if (!mounted) return;
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
    final postUrl = _controller.journalUrl;
    final shareContent = postUrl;
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

        if (!mounted) return;
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
    final commentSettings = context.watch<CommentSettingsProvider>();
    final journalTimeFormat =
        context.select<TimeDisplaySettingsProvider, TimeDisplayFormat>(
      (settings) => settings.formatFor(
        TimeDisplayOccasion.journalPublication,
      ),
    );
    final formattedPublicationTime = _controller.formattedPublicationTime(
      format: journalTimeFormat,
    );
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
                        settings:
                            const AnalyticsRouteSettings(AppScreens.editJournal),
                        builder: (context) => CreateJournalScreen(
                          journalId: widget.journalId,
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
              itemBuilder: (BuildContext context) => buildJournalActionMenu(isOwner: isOwner),
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
                                        buildJournalAuthorHeader(
                                          profileImageUrl: profileImageUrl,
                                          authorDisplayName: authorDisplayName,
                                          authorUserName: authorUserName,
                                          authorSymbol: authorSymbol,
                                          authorUserTitle: authorUserTitle,
                                          isJournalClassic: isJournalClassic,
                                          onAuthorTap: () {
                                            if (authorUserName != null &&
                                                authorUserName!.isNotEmpty) {
                                              Navigator.push(
                                                context,
                                                UserProfileScreen.route(
                                                  nickname: authorUserName!,
                                                ),
                                              );
                                            }
                                          },
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
                                                'Posted on: ${formattedPublicationTime ?? ''}',
                                              ),
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
                                            child: buildJournalBody(
                                              submissionDescription:
                                                  submissionDescription,
                                              onLinkTap: (url) => handleFALink(
                                                context,
                                                url!,
                                                htmlSource:
                                                    submissionDescription,
                                                getFullUrl:
                                                    _controller.getFullLink,
                                              ),
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
                              child: Divider(
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
                              child: Divider(
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
                              sliver: SliverThreadedComments(
                                comments: comments,
                                collapsible: commentSettings.collapsibleCommentsEnabled,
                                itemBuilder: (context, item) {
                                  final index = item.index;
                                  final comment = item.comment;
                                  final selectionId =
                                      _commentSelectionId(comment, index);
                                  return JournalCommentWidget(
                                      key: ValueKey(
                                          comment['commentId'] ?? index),
                                      comment: comment,
                                      treeLevels: item.treeLevels,
                                      collapsed: item.collapsed,
                                      onToggleCollapse:
                                          item.onToggleCollapse,
                                      hasAnyCommentSelection: () =>
                                          _commentSelectedTexts.isNotEmpty,
                                      animationDuration:
                                          item.animationDuration,
                                      animationCurve: item.animationCurve,
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
                                                  settings:
                                                      const AnalyticsRouteSettings(
                                                    AppScreens
                                                        .editJournalComment,
                                                  ),
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
                                            settings:
                                                const AnalyticsRouteSettings(
                                              AppScreens.journalReply,
                                            ),
                                            builder: (context) =>
                                                JournalReplyScreen(
                                              submissionId: widget.journalId,
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
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: ValueListenableBuilder<int>(
                                valueListenable: _commentDraftCollapsedLines,
                                builder: (context, collapsedPreviewLines, _) {
                                  final composerSpacerHeight =
                                      inlineCommentComposerClearance(
                                    collapsedLines: collapsedPreviewLines,
                                    viewPaddingBottom: viewPaddingBottom,
                                  );
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
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: InlineCommentComposer(
                      controller: _commentController,
                      focusNode: _commentFocusNode,
                      keyboardInset: _keyboardInset,
                      isExpanded: _isCommentComposerExpanded,
                      collapsedLines: _commentDraftCollapsedLines,
                      hasText: _commentDraftHasText,
                      showScrollToTop: _showScrollToTopNotifier,
                      isSending: _isSendingInlineComment,
                      viewPaddingBottom: viewPaddingBottom,
                      scrollToTopHeroTag: 'journal_scroll_top',
                      onPointerDown: _handleCommentComposerPointerDown,
                      onScrollToTop: () {
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      onSend: _sendInlineComment,
                      onKeyboardClosing: _dismissCommentComposerFocus,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String fixTruncatedLinks(String htmlContent) {
    return _controller.fixTruncatedLinks(htmlContent);
  }
}
