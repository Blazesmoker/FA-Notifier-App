import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'package:FANotifier/features/auth/domain/cloudflare_check_gateway.dart';
import 'package:FANotifier/features/auth/domain/cloudflare_check_result.dart';
import 'package:FANotifier/shared/fa/fa_webview_document_scripts.dart';

class CloudflareCheckScreen extends StatefulWidget {
  final String initialUrl;
  final bool returnPageHtml;

  const CloudflareCheckScreen({
    super.key,
    this.initialUrl = 'https://www.furaffinity.net/',
    this.returnPageHtml = false,
  });

  @override
  State<CloudflareCheckScreen> createState() => _CloudflareCheckScreenState();
}

class _CloudflareCheckScreenState extends State<CloudflareCheckScreen> {
  InAppWebViewController? _controller;
  bool _didComplete = false;
  late final CloudflareCheckGateway _gateway;

  @override
  void initState() {
    super.initState();
    _gateway = context.read<CloudflareCheckGateway>();
  }

  Future<void> _setCookiesFromSecureStorage() async {
    await _gateway.setStoredCookies();
  }

  Future<void> _saveCookiesToSecureStorage() async {
    final controller = _controller;
    await _gateway.saveCurrentCookies(
      evaluateJavascript: controller == null
          ? null
          : (source) async =>
              await controller.evaluateJavascript(source: source),
    );
  }

  Future<bool> _verifyHttpAccess(String url) async {
    return _gateway.verifyHttpAccess(
      url: url,
      beforeRetryAttempt: _saveCookiesToSecureStorage,
    );
  }

  Future<void> _completeIfChallengePassed({String? urlOverride}) async {
    if (_didComplete || _controller == null || !mounted) return;

    final currentUrl =
        urlOverride ?? (await _controller!.getUrl())?.toString() ?? '';
    if (currentUrl.isEmpty ||
        currentUrl == 'about:blank' ||
        !_gateway.isFaUrl(currentUrl)) {
      return;
    }

    String body = '';
    try {
      final html = await _controller!.evaluateJavascript(
        source: faDocumentOuterHtmlScript,
      );
      body = (html ?? '').toString();
    } catch (_) {
      return;
    }

    final isChallenge = _gateway.isChallengePage(
      url: currentUrl,
      body: body,
    );

    if (isChallenge) {
      debugPrint('[Cloudflare] WebView is still on a challenge page: $currentUrl');
      return;
    }

    final verified = await _verifyHttpAccess(currentUrl);
    if (!verified || !mounted) {
      debugPrint(
        '[Cloudflare] WebView loaded a normal page but HTTP verification is still failing.',
      );
      return;
    }

    if (widget.returnPageHtml) {
      _didComplete = true;
      if (mounted) {
        Navigator.of(context).pop(
          CloudflareCheckResult(
            passed: true,
            pageHtml: body,
            finalUrl: currentUrl,
          ),
        );
      }
      return;
    }

    _didComplete = true;
    if (mounted) {
      Navigator.of(context).pop(const CloudflareCheckResult(passed: true));
    }
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Cloudflare Check'),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(
                  const CloudflareCheckResult(passed: false),
                );
              },
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
        body: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri('about:blank'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            supportZoom: true,
            userAgent: _gateway.userAgent,
          ),
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            return NavigationActionPolicy.ALLOW;
          },
          onWebViewCreated: (controller) async {
            _controller = controller;
            await _setCookiesFromSecureStorage();
            await controller.loadUrl(
              urlRequest: URLRequest(
                url: WebUri(widget.initialUrl),
              ),
            );
          },
          onLoadStop: (controller, url) async {
            final currentUrl = url?.toString() ?? '';
            if (!_gateway.isFaUrl(currentUrl)) {
              return;
            }
            await _saveCookiesToSecureStorage();
            await Future.delayed(const Duration(milliseconds: 250));
            await _completeIfChallengePassed(urlOverride: currentUrl);
          },
        ),
      ),
    );
  }
}
