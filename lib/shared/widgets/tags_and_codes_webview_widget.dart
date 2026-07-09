import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:FANotifier/shared/fa/tags_and_codes_webview_document.dart';

class InfoIconButton extends StatelessWidget {
  final String url;
  final String title;

  const InfoIconButton({
    Key? key,
    this.url = 'https://www.furaffinity.net/help/#tags-and-codes',
    this.title = 'Tags & Codes',
  }) : super(key: key);

  Future<void> _openDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const InfoWebViewDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: IconButton(
        tooltip: title,
        icon: const Icon(Icons.info_outline),
        onPressed: () => _openDialog(context),
      ),
    );
  }
}

class InfoWebViewDialog extends StatefulWidget {
  const InfoWebViewDialog({Key? key}) : super(key: key);

  @override
  State<InfoWebViewDialog> createState() => _InfoWebViewDialogState();
}

class _InfoWebViewDialogState extends State<InfoWebViewDialog> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;


  @override
  void dispose() {
    try {
      _controller?.stopLoading();
    } catch (_) {}
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: ds.width,
        height: ds.height,
        child: SafeArea(
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
              elevation: 1,
              centerTitle: true,
              title: InkWell(
                onTap: () async {
                  final uri = Uri.parse(
                    'https://www.furaffinity.net/help/#tags-and-codes',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.open_in_new,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text('Tags & Codes'),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),

            body: Stack(
              children: [
                InAppWebView(
                  initialData: InAppWebViewInitialData(
                    data: tagsAndCodesWebViewHtml,
                    baseUrl: WebUri('https://www.furaffinity.net/help/#tags-and-codes'),
                    encoding: 'utf-8',
                    mimeType: 'text/html',
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    verticalScrollBarEnabled: true,
                    horizontalScrollBarEnabled: false,
                    transparentBackground: true,
                  ),
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url;
                    if (url == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (!navigationAction.isForMainFrame) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (navigationAction.navigationType == NavigationType.LINK_ACTIVATED) {
                      final uri = Uri.tryParse(url.toString());
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onWebViewCreated: (controller) {
                    _controller = controller;
                  },
                  onLoadStop: (controller, uri) {
                    if (!mounted) return;
                    setState(() {
                      _isLoading = false;
                      _errorMessage = null;
                    });
                  },
                  onContentSizeChanged: (controller, oldContentSize, newContentSize) {
                    if (!mounted || !_isLoading) return;
                    if (newContentSize.width > 0 || newContentSize.height > 0) {
                      setState(() {
                        _isLoading = false;
                        _errorMessage = null;
                      });
                    }
                  },
                  onReceivedError: (controller, request, error) {
                    if (!mounted) return;
                    setState(() {
                      _isLoading = false;
                      _errorMessage =
                          'Page load error: ${error.description} (code ${error.type})';
                    });
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    try {
                      print('Console: ${consoleMessage.message}');
                    } catch (_) {}
                  },
                ),
                if (_isLoading)
                  const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                if (!_isLoading && _errorMessage != null)
                  Positioned.fill(
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _errorMessage!,
                                style: const TextStyle(fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Open full page in browser'),
                                onPressed: () async {
                                  final uri = Uri.tryParse('https://www.furaffinity.net/help/#tags-and-codes');
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Cannot open external browser')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
