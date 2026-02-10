import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/fa_cookie_helper.dart';

class CloudflareCheckScreen extends StatefulWidget {
  const CloudflareCheckScreen({super.key});

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

    // Keep last known cf_clearance if current WebView cookie list omits it.
    if ((latestCf == null || latestCf.isEmpty) &&
        existingCf != null &&
        existingCf.isNotEmpty) {
      await _secureStorage.write(key: 'fa_cookie_cf_clearance', value: existingCf);
    } else if (latestCf != null && latestCf.isNotEmpty) {
      await FaCookieHelper.writeCfClearance(latestCf);
    }
  }

  Future<void> _completeIfChallengePassed() async {
    if (_didComplete || _controller == null || !mounted) return;

    final html = await _controller!.evaluateJavascript(
      source: 'document.documentElement.outerHTML;',
    );
    final body = (html ?? '').toString();
    final isChallenge = FaCookieHelper.isCloudflareChallengePage(body: body);
    final cfClearance = await _secureStorage.read(key: 'fa_cookie_cf_clearance');

    if (!isChallenge && cfClearance != null && cfClearance.isNotEmpty) {
      _didComplete = true;
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
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
          ),
          onWebViewCreated: (controller) async {
            _controller = controller;
            await _setCookiesFromSecureStorage();
            await controller.loadUrl(
              urlRequest: URLRequest(
                url: WebUri('https://www.furaffinity.net/'),
              ),
            );
          },
          onLoadStop: (controller, url) async {
            final currentUrl = url?.toString() ?? '';
            if (!currentUrl.contains('furaffinity.net')) {
              return;
            }
            await _saveCookiesToSecureStorage();
            await _completeIfChallengePassed();
          },
        ),
      ),
    );
  }
}
