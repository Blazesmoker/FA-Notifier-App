import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_check_gateway.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_check_result.dart';
import 'package:fanotifier/features/auth/domain/cloudflare_http_access_result.dart';
import 'package:fanotifier/shared/fa/fa_webview_document_scripts.dart';
import 'package:fanotifier/shared/widgets/fa_unavailable_screen.dart';

class CloudflareCheckScreen extends StatefulWidget {
  final String initialUrl;
  final bool returnPageHtml;
  static Future<CloudflareCheckResult?>? _activeCheck;

  const CloudflareCheckScreen({
    super.key,
    this.initialUrl = 'https://www.furaffinity.net/',
    this.returnPageHtml = false,
  });

  static Future<CloudflareCheckResult?> show(
    BuildContext context, {
    String initialUrl = 'https://www.furaffinity.net/',
    bool returnPageHtml = false,
    bool asDialog = false,
  }) async {
    final active = _activeCheck;
    if (active != null) {
      final result = await active;
      return result == null
          ? null
          : CloudflareCheckResult(
              passed: result.passed,
              siteUnavailableMessage: result.siteUnavailableMessage,
            );
    }
    final screen = CloudflareCheckScreen(
      initialUrl: initialUrl,
      returnPageHtml: returnPageHtml,
    );
    final future = asDialog
        ? showDialog<CloudflareCheckResult>(
            context: context,
            barrierDismissible: false,
            useSafeArea: false,
            routeSettings: const AnalyticsRouteSettings(AppScreens.cloudflareCheck),
            builder: (_) => screen,
          )
        : Navigator.of(context).push<CloudflareCheckResult>(
            MaterialPageRoute<CloudflareCheckResult>(
              settings: const AnalyticsRouteSettings(AppScreens.cloudflareCheck),
              builder: (_) => screen,
            ),
          );
    _activeCheck = future;
    try {
      return await future;
    } finally {
      if (identical(_activeCheck, future)) _activeCheck = null;
    }
  }

  @override
  State<CloudflareCheckScreen> createState() => _CloudflareCheckScreenState();
}

class _CloudflareCheckScreenState extends State<CloudflareCheckScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  bool _didComplete = false;
  bool _isChecking = false;
  bool _isRetrying = false;
  bool _browserGranted = false;
  bool _isResumed = true;
  Timer? _completionTimer;
  int _navigationGeneration = 0;
  int _verificationPasses = 0;
  int? _responseStatus;
  String? _responseUrl;
  Map<String, String>? _responseHeaders;
  String? _verificationError;
  String? _siteUnavailableMessage;
  DateTime? _nextVerificationAt;
  late final CloudflareCheckGateway _gateway;

  @override
  void initState() {
    super.initState();
    _gateway = context.read<CloudflareCheckGateway>();
    _isResumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isResumed = state == AppLifecycleState.resumed;
    if (_isResumed) unawaited(_completeIfChallengePassed());
  }

  void _recordResponse(
    String url,
    int? statusCode,
    Map<String, String>? headers,
  ) {
    if (!_gateway.isFaUrl(url)) return;
    _responseUrl = url;
    _responseStatus = statusCode;
    _responseHeaders = {
      for (final entry in (headers ?? <String, String>{}).entries)
        if (entry.key.toLowerCase() == 'cf-mitigated' ||
            entry.key.toLowerCase() == 'retry-after')
          entry.key: entry.value,
    };
  }

  Future<void> _completeIfChallengePassed() async {
    final controller = _controller;
    if (_didComplete ||
        _isChecking ||
        _isRetrying ||
        !_isResumed ||
        controller == null ||
        !mounted ||
        _siteUnavailableMessage != null ||
        _verificationError != null ||
        _verificationPasses >= 3 ||
        (_nextVerificationAt != null &&
            DateTime.now().isBefore(_nextVerificationAt!))) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return;

    final generation = _navigationGeneration;
    bool isCurrent() =>
        mounted &&
        !_didComplete &&
        _isResumed &&
        generation == _navigationGeneration &&
        ModalRoute.of(context)?.isCurrent != false;

    _isChecking = true;
    try {
      final currentUrl = (await controller.getUrl())?.toString() ?? '';
      if (!isCurrent() || !_gateway.isFaUrl(currentUrl)) return;

      final html = await controller.evaluateJavascript(
        source: "document.readyState === 'loading' ? null : "
            '$faDocumentOuterHtmlScript',
      );
      if (!isCurrent() || html is! String) return;
      final status = _responseUrl == currentUrl ? _responseStatus : null;
      final headers = _responseUrl == currentUrl ? _responseHeaders : null;
      final page = _gateway.classifyPage(
        url: currentUrl,
        body: html,
        statusCode: status,
        headers: headers,
      );
      if (page.status == CloudflareHttpAccessStatus.siteUnavailable) {
        _setSiteUnavailable(page.siteUnavailableMessage!);
        return;
      }
      if (!page.granted) {
        if (page.status == CloudflareHttpAccessStatus.challenged) {
          return;
        }
        if (status != null && status >= 400) {
          _setVerificationError('Fur Affinity could not load. Please try again.');
        }
        return;
      }

      if (!_browserGranted) {
        setState(() => _browserGranted = true);
      }
      final hasClearance = await _gateway.saveCurrentCookies(
        url: currentUrl,
        evaluateJavascript: (source) =>
            controller.evaluateJavascript(source: source),
        isCancelled: () => !isCurrent(),
      );
      if (!isCurrent()) return;
      if (kDebugMode) {
        debugPrint(
          '[Cloudflare] Browser document accepted, status=$status, '
          'clearanceAvailable=$hasClearance, attempt=${_verificationPasses + 1}',
        );
      }

      final verified = await _gateway.verifyHttpAccess(
        url: widget.initialUrl,
        isCancelled: () => !isCurrent(),
      );
      if (!isCurrent()) return;
      if (verified.status == CloudflareHttpAccessStatus.siteUnavailable) {
        _setSiteUnavailable(verified.siteUnavailableMessage!);
        return;
      }
      _verificationPasses++;
      if (!verified.granted) {
        if (_verificationPasses >= 3) {
          _setVerificationError(
            'Fur Affinity opened, but the app could not connect yet. '
            'Please try again.',
          );
        } else {
          _nextVerificationAt = DateTime.now().add(const Duration(seconds: 2));
        }
        return;
      }

      await _gateway.accessVerified();
      if (!isCurrent()) return;
      _finish(CloudflareCheckResult(
        passed: true,
        pageHtml: widget.returnPageHtml ? verified.pageHtml : null,
        finalUrl: widget.returnPageHtml ? verified.finalUrl : null,
      ));
    } catch (_) {
      if (isCurrent()) {
        _setVerificationError('Unable to finish verification. Please try again.');
        if (kDebugMode) {
          debugPrint('[Cloudflare] Completion check unavailable.');
        }
      }
    } finally {
      _isChecking = false;
    }
  }

  void _setVerificationError(String message) {
    if (!mounted || _didComplete) return;
    setState(() => _verificationError = message);
  }

  void _setSiteUnavailable(String message) {
    if (!mounted || _didComplete) return;
    _completionTimer?.cancel();
    _completionTimer = null;
    setState(() {
      _siteUnavailableMessage = message;
      _verificationError = null;
      _browserGranted = false;
    });
  }

  Future<void> _retryVerification() async {
    final controller = _controller;
    if (controller == null ||
        _isChecking ||
        _isRetrying ||
        _didComplete ||
        !_isResumed ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _isRetrying = true;
    final generation = _navigationGeneration;
    bool isCurrent() =>
        mounted &&
        !_didComplete &&
        _isResumed &&
        generation == _navigationGeneration &&
        ModalRoute.of(context)?.isCurrent != false;
    try {
      if (_siteUnavailableMessage != null) {
        await _gateway.waitForSiteRetry(isCancelled: () => !isCurrent());
      }
      if (!isCurrent()) return;
      setState(() {
        _siteUnavailableMessage = null;
        _verificationError = null;
        _verificationPasses = 0;
        _nextVerificationAt = null;
      });
      if (_browserGranted) {
        _isRetrying = false;
        await _completeIfChallengePassed();
      } else {
        await _gateway.setStoredCookies();
        if (!isCurrent()) return;
        _completionTimer ??= Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => unawaited(_completeIfChallengePassed()),
        );
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(widget.initialUrl)),
        );
      }
    } catch (_) {
      if (isCurrent()) {
        _setVerificationError('Unable to load verification. Please try again.');
      }
    } finally {
      _isRetrying = false;
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
    WidgetsBinding.instance.removeObserver(this);
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
          title: Text(
            _siteUnavailableMessage == null ? 'Cloudflare Check' : 'Fur Affinity',
          ),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: () => _finish(
                CloudflareCheckResult(
                  passed: false,
                  siteUnavailableMessage: _siteUnavailableMessage,
                ),
              ),
              child: const Text('Close', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: _siteUnavailableMessage != null,
                child: Column(
                  children: [
                    Expanded(
                      child: InAppWebView(
                        initialUrlRequest: URLRequest(url: WebUri('about:blank')),
                        initialSettings: InAppWebViewSettings(
                          transparentBackground:
                              defaultTargetPlatform == TargetPlatform.iOS,
                          underPageBackgroundColor:
                              defaultTargetPlatform == TargetPlatform.iOS
                                  ? Colors.black
                                  : null,
                          javaScriptEnabled: true,
                          useShouldOverrideUrlLoading: true,
                          useOnNavigationResponse: true,
                          supportZoom: true,
                          userAgent: _gateway.userAgent,
                        ),
                        shouldOverrideUrlLoading: (controller, action) async {
                          final url = action.request.url?.toString() ?? '';
                          if (action.isForMainFrame &&
                              !_gateway.isFaUrl(url) &&
                              url != 'about:blank') {
                            return NavigationActionPolicy.CANCEL;
                          }
                          return NavigationActionPolicy.ALLOW;
                        },
                        onWebViewCreated: (controller) async {
                          _controller = controller;
                          try {
                            await _gateway.setStoredCookies();
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
                          } catch (_) {
                            _setVerificationError(
                              'Unable to prepare verification. Please try again.',
                            );
                          }
                        },
                        onLoadStart: (controller, url) {
                          _navigationGeneration++;
                          _verificationPasses = 0;
                          _nextVerificationAt = null;
                          _responseStatus = null;
                          _responseHeaders = null;
                          _responseUrl = null;
                          if (mounted && !_didComplete) {
                            setState(() {
                              _browserGranted = false;
                              _verificationError = null;
                            });
                          }
                        },
                        onNavigationResponse:
                            (controller, navigationResponse) async {
                          final response = navigationResponse.response;
                          if (navigationResponse.isForMainFrame &&
                              response != null) {
                            _recordResponse(
                              response.url?.toString() ?? '',
                              response.statusCode,
                              response.headers,
                            );
                          }
                          return NavigationResponseAction.ALLOW;
                        },
                        onPageCommitVisible: (controller, url) {
                          unawaited(_completeIfChallengePassed());
                        },
                        onLoadStop: (controller, url) async {
                          await _completeIfChallengePassed();
                        },
                        onReceivedHttpError: (controller, request, response) {
                          if (request.isForMainFrame != true) return;
                          _recordResponse(
                            request.url.toString(),
                            response.statusCode,
                            response.headers,
                          );
                        },
                        onReceivedError: (controller, request, error) {
                          if (request.isForMainFrame != true ||
                              error.type == WebResourceErrorType.CANCELLED ||
                              _browserGranted) {
                            return;
                          }
                          _setVerificationError(
                            'Unable to load verification. Please try again.',
                          );
                        },
                      ),
                    ),
                    if (_browserGranted || _verificationError != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _verificationError ?? 'Finishing verification…',
                              textAlign: TextAlign.center,
                            ),
                            if (_verificationError != null)
                              TextButton(
                                onPressed: _retryVerification,
                                child: const Text('Retry'),
                              )
                            else ...[
                              const SizedBox(height: 12),
                              const LinearProgressIndicator(),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (_siteUnavailableMessage != null)
                Positioned.fill(
                  child: FaUnavailableScreen(
                    title: 'Fur Affinity is temporarily offline',
                    message: _siteUnavailableMessage!,
                    onRefresh: _retryVerification,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
