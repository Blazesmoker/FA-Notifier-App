import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/features/ads/domain/fa_ads_repository.dart';
import 'package:fanotifier/features/ads/domain/fa_webview_ad_gateway.dart';
import 'package:fanotifier/shared/navigation/fa_link_handler.dart';

class FaWebViewAdController with WidgetsBindingObserver {
  FaWebViewAdController({
    required this._context,
    required this._repository,
    required this._gateway,
  }) {
    WidgetsBinding.instance.addObserver(this);
    final settings = PlatformInAppWebViewController.debugLoggingSettings;
    final filters = [
      RegExp('faWebViewAdTap'),
      RegExp(r'rv\.furaffinity\.net/live/www/delivery/(?:cl|ck)\.php'),
    ];
    settings.excludeFilter = [
      ...settings.excludeFilter,
      for (final filter in filters)
        if (!settings.excludeFilter.any(
          (existing) => existing.pattern == filter.pattern,
        ))
          filter,
    ];
  }

  final BuildContext _context;
  final FaAdsRepository _repository;
  final FaWebViewAdGateway _gateway;
  InAppWebViewController? _controller;
  Uri? _documentUri;
  FaAdCancellation? _clickCancellation;
  int _generation = 0;
  bool _opening = false;
  bool _disposed = false;

  late final UnmodifiableListView<UserScript> initialUserScripts =
      UnmodifiableListView<UserScript>([
        UserScript(
          source: _gateway.tapHandlerScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ]);

  bool get _canOpen {
    if (_disposed || !_context.mounted) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    return (state == null || state == AppLifecycleState.resumed) &&
        (ModalRoute.of(_context)?.isCurrent ?? true);
  }

  void attach(InAppWebViewController controller) {
    if (_disposed) return;
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: 'faWebViewAdTap',
      callback: (JavaScriptHandlerFunctionData data) async {
        if (!data.isMainFrame || data.args.length != 1) return;
        final documentUri = Uri.tryParse(data.requestUrl.toString());
        final origin = Uri.tryParse(data.origin.toString());
        final payload = data.args.single;
        if (documentUri == null ||
            origin == null ||
            payload is! Map ||
            !_gateway.isSupportedDocument(documentUri) ||
            origin.scheme != documentUri.scheme ||
            origin.host != documentUri.host ||
            origin.port != documentUri.port ||
            !_isCurrentDocument(documentUri)) {
          return;
        }
        final href = payload['href'];
        final slot = payload['placement'];
        if (href is! String ||
            slot is! String ||
            !FaAdPlacement.values.any(
              (placement) => placement.websiteId == slot,
            )) {
          return;
        }
        final clickUri = Uri.tryParse(href);
        if (clickUri == null) return;
        await _openClick(clickUri, documentUri, slot: slot);
      },
    );
  }

  void documentStarted(WebUri? url) {
    if (_disposed) return;
    _generation++;
    _clickCancellation?.cancel();
    _documentUri = url == null ? null : Uri.tryParse(url.toString());
  }

  Future<void> documentLoaded(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    if (_disposed || url == null) return;
    final uri = Uri.tryParse(url.toString());
    if (uri == null || !_gateway.isSupportedDocument(uri)) return;
    if (!_isCurrentDocument(uri)) documentStarted(url);
    try {
      await controller.evaluateJavascript(source: _gateway.tapHandlerScript);
    } catch (_) {
      FaAdsLog.event(FaAdsLogCategory.click, 'webview_handler_unavailable');
    }
  }

  bool interceptNavigation(NavigationAction action) {
    final uri = action.request.url;
    final documentUri = _documentUri;
    if (_disposed ||
        uri == null ||
        documentUri == null ||
        !_gateway.isSupportedDocument(documentUri) ||
        !_gateway.isTrackingClick(uri) ||
        (action.request.method ?? 'GET').toUpperCase() != 'GET' ||
        (!action.isForMainFrame && action is! CreateWindowAction)) {
      return false;
    }
    if (action.hasGesture == true ||
        action.navigationType == NavigationType.LINK_ACTIVATED) {
      unawaited(_openClick(uri, documentUri));
    }
    return true;
  }

  Future<bool> onCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction action,
  ) async {
    if (interceptNavigation(action)) return false;
    if (!_disposed && Platform.isAndroid && action.request.url != null) {
      await controller.loadUrl(urlRequest: action.request);
    }
    return false;
  }

  bool _isCurrentDocument(Uri uri) =>
      _documentUri?.replace(fragment: '') == uri.replace(fragment: '');

  Future<void> _openClick(
    Uri clickUri,
    Uri documentUri, {
    String? slot,
  }) async {
    if (_opening ||
        !_canOpen ||
        (clickUri.scheme != 'https' && clickUri.scheme != 'http') ||
        clickUri.host.isEmpty ||
        clickUri.userInfo.isNotEmpty) {
      return;
    }
    _opening = true;
    final cancellation = FaAdCancellation();
    _clickCancellation = cancellation;
    final generation = _generation;
    bool canStart() =>
        _canOpen &&
        !cancellation.isCancelled &&
        generation == _generation &&
        _isCurrentDocument(documentUri);
    try {
      final page = await _gateway.readPageContext(documentUri);
      if (!canStart()) return;
      final tracking = _gateway.isTrackingClick(clickUri);
      final destination = tracking
          ? await _repository.resolveClickUrl(
              clickUri: clickUri,
              page: page,
              cancellation: cancellation,
              canStart: canStart,
            )
          : clickUri;
      if (!canStart() || !_context.mounted) return;
      final disposition = await handleFAAdDestination(_context, destination);
      FaAdsLog.event(FaAdsLogCategory.click, 'destination_handed_off',
          slot: slot,
          checks: {
            'sourceWebView': true,
            'internal': disposition == FaAdLinkDisposition.internal,
            'external': disposition == FaAdLinkDisposition.external,
            'opened': disposition != FaAdLinkDisposition.failed,
            'confirmationSkippedForAd': true,
            'trackingResolved': tracking,
            'trackingUrlOpenedTwice': false,
          });
    } catch (_) {
      FaAdsLog.event(FaAdsLogCategory.click, 'webview_handoff_failed',
          slot: slot,
          checks: {'cancelled': !canStart(), 'willRetry': false});
    } finally {
      if (identical(_clickCancellation, cancellation)) {
        _clickCancellation = null;
        _opening = false;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clickCancellation?.cancel();
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _clickCancellation?.cancel();
    _controller?.removeJavaScriptHandler(handlerName: 'faWebViewAdTap');
    _controller = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}
