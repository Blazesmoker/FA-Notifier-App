import 'dart:async';

import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:FANotifier/features/notes/domain/note_reply_repository.dart';
import 'package:FANotifier/features/notes/domain/note_reply_webview_gateway.dart';
import 'package:FANotifier/features/notes/presentation/note_reply_webview_controller_factory.dart';
import 'package:FANotifier/features/notes/domain/note_image_preview_mode.dart';
import 'package:FANotifier/features/notes/domain/note_submission_preview_repository.dart';
import 'package:FANotifier/features/notes/presentation/note_body_with_previews.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/navigation/fa_link_handler.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:FANotifier/shared/widgets/cooldown_send_icon.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';
import 'package:provider/provider.dart';

class NoteReplyScreen extends StatefulWidget {
  final String subject;
  final String originalContent;
  final String? originalContentHtml;
  final String username;
  final String messageId;
  final String messageLink;
  final NoteImagePreviewMode imagePreviewMode;

  const NoteReplyScreen({
    Key? key,
    required this.subject,
    required this.originalContent,
    this.originalContentHtml,
    required this.username,
    required this.messageId,
    required this.messageLink,
    required this.imagePreviewMode,
  }) : super(key: key);

  @override
  _NoteReplyScreenState createState() => _NoteReplyScreenState();
}

class _NoteReplyScreenState extends State<NoteReplyScreen> {
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;
  Timer? _cooldownTimer;
  int _cooldownRemaining = 0;
  int _cooldownTotal = 0;
  bool _useWebView = false;
  bool _isClassicTheme = false;

  late final NoteReplyRepository _noteReplyRepository;
  late final NoteReplyWebViewGateway _webViewGateway;
  final NoteReplyWebViewControllerFactory _webViewControllerFactory =
      const NoteReplyWebViewControllerFactory();

  late String recipient;
  bool _isMessageDetailsLoading = true;
  String errorMessage = '';

  WebViewController? _webViewController;
  bool _isWebViewInitialized = false;
  bool _showCloudflareMessage = true;
  bool _replySentSuccessfully = false;
  bool _hasPopped = false;
  String _selectedOriginalText = '';
  late final bool _hasImagePreviewLinks;

  @override
  void initState() {
    super.initState();
    recipient = widget.username;
    _hasImagePreviewLinks =
        widget.imagePreviewMode != NoteImagePreviewMode.off &&
            noteBodyContainsSubmissionLinks(
              widget.originalContentHtml != null &&
                      widget.originalContentHtml!.isNotEmpty
                  ? widget.originalContentHtml!
                  : widget.originalContent,
              isHtml: widget.originalContentHtml != null &&
                  widget.originalContentHtml!.isNotEmpty,
            );
    _noteReplyRepository = context.read<NoteReplyRepositoryFactory>()();
    _webViewGateway = context.read<NoteReplyWebViewGateway>();
    _fetchMessageDetails();
  }

  Future<void> _onRequestClose() async {
    final confirmed = await ConfirmCloseDialog.show(context);
    if (confirmed && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _noteReplyRepository.close();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessageDetails() async {
    try {
      final details = await _noteReplyRepository.fetchReplyContext(
        widget.messageLink,
      );

      if (mounted) {
        setState(() {
          recipient = details.recipient;
          _isClassicTheme = details.isClassicTheme;
          _isMessageDetailsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Error fetching details: $e';
          _isMessageDetailsLoading = false;
        });
      }
    }
  }

  Future<void> _initializeWebView() async {
    final hasCookies = await _webViewGateway.setAuthCookies();

    if (!hasCookies) {
      if (mounted) {
        setState(() {
          errorMessage = 'Not logged in or missing cookies.';
          _useWebView = false;
        });
      }
      return;
    }

    final webViewUrl = _webViewGateway.buildMessageUrl(widget.messageLink);

    final WebViewController controller = _webViewControllerFactory.create();

    _webViewControllerFactory.configure(
      controller,
      navigationDelegate: NavigationDelegate(
          onPageStarted: (String url) {
            // Check if we've navigated to the messages list (success)
            debugPrint('DEBUG: WebView page started: $url');
            if (_webViewGateway.isSentMessagesListUrl(url)) {
              debugPrint('DEBUG: Success detected in onPageStarted');
              if (mounted && !_replySentSuccessfully) {
                debugPrint('DEBUG: Setting _replySentSuccessfully = true in onPageStarted');
                setState(() {
                  _replySentSuccessfully = true;
                  _useWebView = false;
                  _isSending = false;
                });
              }
            }
          },
          onPageFinished: (String url) async {
            debugPrint('DEBUG: WebView page finished: $url');
            await _injectFormHandler(controller);
            if (mounted) {
              setState(() {
                _isWebViewInitialized = true;
              });
            }

            // Double-check for success page
            if (_webViewGateway.isSentMessagesListUrl(url)) {
              debugPrint('DEBUG: Success detected in onPageFinished');
              if (mounted && !_replySentSuccessfully) {
                debugPrint('DEBUG: Setting _replySentSuccessfully = true in onPageFinished');
                setState(() {
                  _replySentSuccessfully = true;
                  _useWebView = false;
                  _isSending = false;
                });
              }
            }
          },
        ),
    );

    await controller.loadRequest(Uri.parse(webViewUrl));

    if (mounted) {
      setState(() {
        _webViewController = controller;
      });
    }
  }

  void _updatePlainOriginalSelection(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    if (!selection.isValid || selection.isCollapsed) {
      _selectedOriginalText = '';
      return;
    }
    final start =
        selection.start < selection.end ? selection.start : selection.end;
    final end =
        selection.start < selection.end ? selection.end : selection.start;
    _selectedOriginalText = widget.originalContent.substring(start, end);
  }

  Future<void> _injectFormHandler(WebViewController controller) async {
    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) return;

    await controller.runJavaScript(
      _webViewGateway.buildFormScript(
        replyText: replyText,
        originalContent: widget.originalContent,
        recipient: recipient,
        subject: widget.subject,
      ),
    );
  }

  Future<void> _sendReplyModern() async {
    if (_isSending || _cooldownRemaining > 0) return;

    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply cannot be empty.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _isSending = true;
      errorMessage = '';
    });

    try {
      final result = await _noteReplyRepository.sendModernReply(
        messageLink: widget.messageLink,
        recipient: recipient,
        subject: widget.subject,
        replyText: replyText,
        originalContent: widget.originalContent,
      );

      if (result.success) {
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        final message = result.errorMessage ?? 'Failed to send reply.';
        final retryAfter = result.retryAfterSeconds;
        final isWaitingToRetry = retryAfter != null && retryAfter > 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red,
              duration: isWaitingToRetry
                  ? const Duration(seconds: 6)
                  : const Duration(seconds: 4),
            ),
          );
        }
        if (retryAfter != null && retryAfter > 0) {
          _startCooldown(retryAfter);
        }
      }
    } catch (e) {
      final message = 'Error sending reply: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _sendReply() async {
    if (_isSending || _cooldownRemaining > 0) return;

    final replyText = _replyController.text.trim();
    if (replyText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply cannot be empty.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (_isClassicTheme) {
      setState(() {
        _useWebView = true;
        _isSending = true;
      });
      await _initializeWebView();
    } else {
      await _sendReplyModern();
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
    debugPrint('DEBUG: NoteReplyScreen build() - _replySentSuccessfully: $_replySentSuccessfully, _useWebView: $_useWebView, _hasPopped: $_hasPopped');

    // If reply was sent successfully via WebView, show success and close
    if (_replySentSuccessfully && !_useWebView && !_hasPopped) {
      debugPrint('DEBUG: Conditions met, setting _hasPopped = true and scheduling pop');
      _hasPopped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('DEBUG: PostFrameCallback executing - mounted: $mounted');
        if (mounted) {
          debugPrint('DEBUG: Calling Navigator.pop(context, true)');
          Navigator.pop(context, true);
        }
      });
    }

    if (_useWebView && _webViewController != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _useWebView = false;
                _isSending = false;
              });
            },
          ),
          title: const Text("Complete Reply"),
          backgroundColor: Colors.black,
        ),
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            WebViewWidget(controller: _webViewController!),
            if (!_isWebViewInitialized)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  backgroundColor: Colors.grey[800],
                ),
              ),
            if (_showCloudflareMessage)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Complete the Cloudflare verification and click "Post" to send your reply.',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () {
                          setState(() {
                            _showCloudflareMessage = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final imagePreviewRepository = _hasImagePreviewLinks
        ? context.read<NoteSubmissionPreviewRepository>()
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) _onRequestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onRequestClose,
          ),
          title: const Text("Reply to Note"),
          actions: [
            IconButton(
              icon: _buildSendIcon(),
              onPressed: (_isSending ||
                      _isMessageDetailsLoading ||
                      _cooldownRemaining > 0)
                  ? null
                  : _sendReply,
            ),
          ],
        ),
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (errorMessage.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                errorMessage,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          if (_isClassicTheme)
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Cloudflare verification is required in Classic theme.',
                                      style: TextStyle(color: Colors.orange, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            'Recipient: $recipient',
                            style: const TextStyle(fontSize: 16, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Subject: ${widget.subject}',
                            style: const TextStyle(fontSize: 16, color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Original Note:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _hasImagePreviewLinks
                                ? Theme(
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
                                      onSelectionChanged: (content) {
                                        _selectedOriginalText =
                                            content?.plainText.replaceAll(
                                                  '\uFFFC',
                                                  '',
                                                ) ??
                                                '';
                                      },
                                      contextMenuBuilder:
                                          ReadOnlySelectionContextMenu.builder(
                                        selectedTextProvider: () =>
                                            _selectedOriginalText,
                                        includeIosTranslate: true,
                                      ),
                                      child: NoteBodyWithPreviews(
                                        content:
                                            widget.originalContentHtml !=
                                                        null &&
                                                    widget.originalContentHtml!
                                                        .isNotEmpty
                                                ? widget.originalContentHtml!
                                                : widget.originalContent,
                                        isHtml:
                                            widget.originalContentHtml !=
                                                        null &&
                                                    widget.originalContentHtml!
                                                        .isNotEmpty,
                                        mode: widget.imagePreviewMode,
                                        repository: imagePreviewRepository!,
                                      ),
                                    ),
                                  )
                                : (widget.originalContentHtml != null &&
                                    widget.originalContentHtml!.isNotEmpty)
                                ? Theme(
                                    data: Theme.of(context).copyWith(
                                      textSelectionTheme: TextSelectionThemeData(
                                        selectionColor: const Color(0xFFE09321).withValues(alpha: 0.4),
                                        selectionHandleColor: const Color(0xFFE09321),
                                      ),
                                    ),
                                    child: SelectionArea(
                                      onSelectionChanged: (content) {
                                        _selectedOriginalText =
                                            content?.plainText ?? '';
                                      },
                                      contextMenuBuilder:
                                          ReadOnlySelectionContextMenu.builder(
                                        selectedTextProvider: () =>
                                            _selectedOriginalText,
                                        includeIosTranslate: true,
                                      ),
                                      child: html_pkg.Html(
                                        data: widget.originalContentHtml!,
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
                                    ),
                                  )
                                : SelectableText(
                                    widget.originalContent,
                                    onSelectionChanged:
                                        _updatePlainOriginalSelection,
                                    contextMenuBuilder:
                                        ReadOnlyEditableTextContextMenu.builder(
                                      selectedTextProvider: () =>
                                          _selectedOriginalText,
                                      includeIosTranslate: true,
                                    ),
                                    style: const TextStyle(fontSize: 16, color: Colors.white),
                                  ),
                          ),
                          const SizedBox(height: 16),
                        ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    controller: _replyController,
                    style: const TextStyle(color: Colors.white),
                    minLines: 6,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Your Reply',
                      hintStyle: TextStyle(color: Colors.white),
                      contentPadding: EdgeInsets.all(16),
                    ),
                    contextMenuBuilder:
                        BBCodeContextMenu.builder(_replyController),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
