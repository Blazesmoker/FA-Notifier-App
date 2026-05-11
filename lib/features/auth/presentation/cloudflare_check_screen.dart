import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';

import 'package:FANotifier/features/auth/domain/cloudflare_check_result.dart';
import 'package:FANotifier/shared/fa/fa_cookie_helper.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

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

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'flutter_secure_storage_service',
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  Future<void> _setCookiesFromSecureStorage() async {
    final cookieKeys = <String>[
      'a',
      'b',
      'cc',
      'cf_clearance',
      'folder',
      'nodesc',
      'sz',
      'sfw',
    ];

    for (final key in cookieKeys) {
      final value = await _secureStorage.read(key: 'fa_cookie_$key');
      if (value == null || value.isEmpty) continue;
      await CookieManager.instance().setCookie(
        url: WebUri('https://www.furaffinity.net'),
        name: key,
        value: value,
        domain: '.furaffinity.net',
        path: '/',
        isHttpOnly: true,
        isSecure: true,
        expiresDate:
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      );
    }
  }

  Future<void> _saveCookiesToSecureStorage() async {
    final existingCf = await _secureStorage.read(key: 'fa_cookie_cf_clearance');
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://www.furaffinity.net'),
    );

    String? latestCf;
    for (final cookie in cookies) {
      await _secureStorage.write(
        key: 'fa_cookie_${cookie.name}',
        value: cookie.value,
      );
      if (cookie.name == 'cf_clearance' && cookie.value.isNotEmpty) {
        latestCf = cookie.value;
      }
    }

    if ((latestCf == null || latestCf.isEmpty) &&
        existingCf != null &&
        existingCf.isNotEmpty) {
      await _secureStorage.write(key: 'fa_cookie_cf_clearance', value: existingCf);
    } else if (latestCf != null && latestCf.isNotEmpty) {
      await FaCookieHelper.writeCfClearance(latestCf);
    }

    if (_controller != null) {
      try {
        final rawDocumentCookie = await _controller!.evaluateJavascript(
          source: 'document.cookie',
        );
        final documentCookie = rawDocumentCookie?.toString() ?? '';
        final cookiePairs = documentCookie.split(';');
        for (final pair in cookiePairs) {
          final separator = pair.indexOf('=');
          if (separator <= 0) continue;
          final name = pair.substring(0, separator).trim();
          final value = pair.substring(separator + 1).trim();
          if (name.isEmpty || value.isEmpty) continue;
          await _secureStorage.write(key: 'fa_cookie_$name', value: value);
          if (name == 'cf_clearance') {
            await FaCookieHelper.writeCfClearance(value);
          }
        }
      } catch (_) {}
    }
  }

  Future<String> _getCookieHeader() async {
    const cookieKeys = <String>[
      'a',
      'b',
      'cc',
      'cf_clearance',
      'folder',
      'nodesc',
      'sz',
      'sfw',
    ];

    final cookies = <String>[];
    for (final key in cookieKeys) {
      final value = await _secureStorage.read(key: 'fa_cookie_$key');
      if (value != null && value.isNotEmpty) {
        cookies.add('$key=$value');
      }
    }
    return cookies.join('; ');
  }

  Future<bool> _verifyHttpAccess(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 250 * attempt));
        await _saveCookiesToSecureStorage();
      }

      final cookieHeader = await FaCookieHelper.appendCfClearanceToCookieHeader(
        await _getCookieHeader(),
      );
      try {
        final response = await FAHttp.get(
          uri,
          headers: {
            if (cookieHeader.isNotEmpty) HttpHeaders.cookieHeader: cookieHeader,
            'User-Agent': FAHttp.userAgent,
            'Referer': 'https://www.furaffinity.net/',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        );

        final refreshedCf = FaCookieHelper.extractCfClearanceFromSetCookieHeader(
          response.headers['set-cookie'],
        );
        if (refreshedCf != null && refreshedCf.isNotEmpty) {
          await FaCookieHelper.writeCfClearance(refreshedCf);
        }

        final isChallenge = FaCookieHelper.isCloudflareChallengePage(
          body: response.body,
          statusCode: response.statusCode,
        );
        debugPrint(
          '[Cloudflare] HTTP verification attempt ${attempt + 1} for $url => '
          'status=${response.statusCode}, challenge=$isChallenge',
        );
        if (!isChallenge) {
          return true;
        }
      } catch (e) {
        debugPrint(
          '[Cloudflare] HTTP verification attempt ${attempt + 1} failed: $e',
        );
      }
    }

    return false;
  }

  Future<void> _completeIfChallengePassed({String? urlOverride}) async {
    if (_didComplete || _controller == null || !mounted) return;

    final currentUrl =
        urlOverride ?? (await _controller!.getUrl())?.toString() ?? '';
    if (currentUrl.isEmpty ||
        currentUrl == 'about:blank' ||
        !currentUrl.contains('furaffinity.net')) {
      return;
    }

    String body = '';
    try {
      final html = await _controller!.evaluateJavascript(
        source: 'document.documentElement.outerHTML;',
      );
      body = (html ?? '').toString();
    } catch (_) {
      return;
    }

    final isChallenge =
        currentUrl.contains('/cdn-cgi/challenge-platform') ||
        FaCookieHelper.isCloudflareChallengePage(body: body);

    if (isChallenge) {
      debugPrint('[Cloudflare] WebView is still on a challenge page: $currentUrl');
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

    final verified = await _verifyHttpAccess(currentUrl);
    if (!verified || !mounted) {
      debugPrint(
        '[Cloudflare] WebView loaded a normal page but HTTP verification is still failing.',
      );
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
            clearCache: false,
            supportZoom: true,
            userAgent: FAHttp.userAgent,
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
            if (!currentUrl.contains('furaffinity.net')) {
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
