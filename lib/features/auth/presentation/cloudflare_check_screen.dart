import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/auth/domain/cloudflare_check_gateway.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_check_result.dart';
import 'package:fanotifier/shared/fa/fa_webview_document_scripts.dart';

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
  bool _isChecking = false;
  Timer? _completionTimer;
  int _navigationGeneration = 0;
  int _verificationPasses = 0;
  DateTime? _nextVerificationAt;
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

  Future<void> _completeIfChallengePassed() async {
    final controller = _controller;
    if (_didComplete || _isChecking || controller == null || !mounted) return;

    final generation = _navigationGeneration;
    bool isCurrent() =>
        mounted && !_didComplete && generation == _navigationGeneration;

    _isChecking = true;
    try {
      final currentUrl = (await controller.getUrl())?.toString() ?? '';
      if (!isCurrent() || !_gateway.isFaUrl(currentUrl)) return;

      final html = await controller.evaluateJavascript(
        source: "document.readyState === 'loading' ? null : "
            '$faDocumentOuterHtmlScript',
      );
      if (!isCurrent() || html == null) return;
      final body = html.toString();
      if (body.trim().isEmpty ||
          _gateway.isChallengePage(url: currentUrl, body: body)) {
        return;
      }

      if (_verificationPasses >= 3 ||
          (_nextVerificationAt != null &&
              DateTime.now().isBefore(_nextVerificationAt!))) {
        return;
      }
      _verificationPasses++;
      await _saveCookiesToSecureStorage();
      if (!isCurrent()) return;
      final verified = await _gateway.verifyHttpAccess(
        url: currentUrl,
        beforeRetryAttempt: () async {
          if (!isCurrent()) throw StateError('Cloudflare check ended');
          await _saveCookiesToSecureStorage();
        },
      );
      if (!isCurrent()) return;
      if (!verified) {
        _nextVerificationAt = DateTime.now().add(const Duration(seconds: 3));
        return;
      }
      if ((await controller.getUrl())?.toString() != currentUrl || !isCurrent()) {
        return;
      }

      _finish(CloudflareCheckResult(
        passed: true,
        pageHtml: widget.returnPageHtml ? body : null,
        finalUrl: widget.returnPageHtml ? currentUrl : null,
      ));
    } catch (_) {
      if (isCurrent()) {
        _nextVerificationAt = DateTime.now().add(const Duration(seconds: 3));
        debugPrint('[Cloudflare] Completion check could not finish.');
      }
    } finally {
      _isChecking = false;
    }
  }

  void _finish(CloudflareCheckResult result) {
    if (_didComplete || !mounted) return;
    _didComplete = true;
    _completionTimer?.cancel();
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
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
                _finish(const CloudflareCheckResult(passed: false));
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
            transparentBackground: defaultTargetPlatform == TargetPlatform.iOS,
            underPageBackgroundColor:
                defaultTargetPlatform == TargetPlatform.iOS ? Colors.black : null,
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
            if (!mounted || _didComplete) return;
            _completionTimer = Timer.periodic(
              const Duration(milliseconds: 500),
              (_) => unawaited(_completeIfChallengePassed()),
            );
            await controller.loadUrl(
              urlRequest: URLRequest(
                url: WebUri(widget.initialUrl),
              ),
            );
          },
          onLoadStart: (controller, url) {
            _navigationGeneration++;
            _verificationPasses = 0;
            _nextVerificationAt = null;
          },
          onPageCommitVisible: (controller, url) {
            unawaited(_completeIfChallengePassed());
          },
          onLoadStop: (controller, url) async {
            await _completeIfChallengePassed();
          },
        ),
      ),
    );
  }
}
