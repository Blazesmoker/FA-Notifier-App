import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:FANotifier/features/notes/data/note_reply_service.dart';
import 'package:FANotifier/features/notes/data/note_reply_webview_cookie_service.dart';
import 'package:FANotifier/features/notes/data/note_reply_webview_navigation_service.dart';
import 'package:FANotifier/features/notes/data/note_reply_webview_scripts.dart';
import 'package:FANotifier/shared/utils/bbcode_context_menu.dart';
import 'package:FANotifier/shared/utils/fa_link_handler.dart';
import 'package:FANotifier/shared/widgets/PulsatingLoadingIndicator.dart';
import 'package:FANotifier/shared/widgets/confirm_close_dialog.dart';
import 'package:FANotifier/shared/widgets/fa_network_image.dart';

class NoteReplyScreen extends StatefulWidget {
  final String subject;
  final String originalContent;
  final String? originalContentHtml;
  final String username;
  final String messageId;
  final String messageLink;

  const NoteReplyScreen({
    Key? key,
    required this.subject,
    required this.originalContent,
    this.originalContentHtml,
    required this.username,
    required this.messageId,
    required this.messageLink,
  }) : super(key: key);

  @override
  _NoteReplyScreenState createState() => _NoteReplyScreenState();
}

class _NoteReplyScreenState extends State<NoteReplyScreen> {
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;
  bool _useWebView = false;
  bool _isClassicTheme = false;

  late final NoteReplyService _noteReplyService =
      NoteReplyService();
  late final NoteReplyWebViewCookieService _webViewCookieService =
      NoteReplyWebViewCookieService();
  final NoteReplyWebViewNavigationService _webViewNavigationService =
      const NoteReplyWebViewNavigationService();

  String recipient = 'Loading...';
  bool _isMessageDetailsLoading = true;
  String errorMessage = '';

  WebViewController? _webViewController;
  bool _isWebViewInitialized = false;
  bool _showCloudflareMessage = true;
  bool _replySentSuccessfully = false;
  bool _hasPopped = false;
  String _selectedOriginalText = '';

  @override
  void initState() {
    super.initState();
    _fetchMessageDetails();
  }

  Future<void> _onRequestClose() async {
    final confirmed = await ConfirmCloseDialog.show(context);
    if (confirmed && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _noteReplyService.close();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessageDetails() async {
    try {
      final details = await _noteReplyService.fetchReplyContext(
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
    final hasCookies = await _webViewCookieService.setAuthCookies();

    if (!hasCookies) {
      if (mounted) {
        setState(() {
          errorMessage = 'Not logged in or missing cookies.';
          _useWebView = false;
        });
      }
      return;
    }

    final webViewUrl =
        _webViewNavigationService.buildMessageUrl(widget.messageLink);

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller = WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            // Check if we've navigated to the messages list (success)
            debugPrint('DEBUG: WebView page started: $url');
            if (_webViewNavigationService.isSentMessagesListUrl(url)) {
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
            if (_webViewNavigationService.isSentMessagesListUrl(url)) {
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
      )
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
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
      buildNoteReplyFormScript(
        replyText: replyText,
        originalContent: widget.originalContent,
        recipient: recipient,
        subject: widget.subject,
      ),
    );
  }

  Future<void> _sendReplyModern() async {
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
      final result = await _noteReplyService.sendModernReply(
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
        errorMessage = result.errorMessage ?? 'Failed to send reply.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      errorMessage = 'Error sending reply: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
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

    if (_isMessageDetailsLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Reply to Note"),
          backgroundColor: Colors.black,
        ),
        backgroundColor: Colors.black,
        body: const Center(
          child: PulsatingLoadingIndicator(
            size: 88.0,
            assetPath: 'assets/icons/fathemed.png',
          ),
        ),
      );
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
              icon: _isSending
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2.0,
                ),
              )
                  : const Icon(Icons.send),
              onPressed: _isSending ? null : _sendReply,
            ),
          ],
        ),
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
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
                            child: (widget.originalContentHtml != null &&
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
                          Expanded(
                            child: TextField(
                              controller: _replyController,
                              style: const TextStyle(color: Colors.white),
                              minLines: 6,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Your Reply',
                                labelStyle: TextStyle(color: Colors.white),
                                alignLabelWithHint: true,
                              ),
                              contextMenuBuilder: BBCodeContextMenu.builder(_replyController),
                            ),

                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
