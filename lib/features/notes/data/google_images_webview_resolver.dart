import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:fanotifier/core/network/fa_request_coordinator.dart';
import 'package:fanotifier/features/notes/domain/note_google_image_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class GoogleImagesWebViewResolver implements NoteGoogleImageResolver {
  GoogleImagesWebViewResolver({
    Duration timeout = const Duration(seconds: 12),
    Duration pollInterval = const Duration(milliseconds: 150),
  })  : _timeout = timeout,
        _pollInterval = pollInterval;

  final Duration _timeout;
  final Duration _pollInterval;
  Future<void> _queue = Future<void>.value();

  @override
  Future<String?> resolveHighQualityImageUrl({
    required Uri pageUri,
    required String selectedId,
  }) {
    final result = Completer<String?>();
    final previous = _queue;
    _queue = () async {
      try {
        await previous;
      } catch (_) {}
      try {
        result.complete(
          await _resolveOne(
            pageUri: pageUri,
            selectedId: selectedId,
          ),
        );
      } catch (error, stackTrace) {
        _logWebViewError(
          'resolver exception selectedId=$selectedId',
          error,
          stackTrace,
        );
        if (!result.isCompleted) result.complete(null);
      }
    }();
    return result.future;
  }

  Future<String?> _resolveOne({
    required Uri pageUri,
    required String selectedId,
  }) async {
    if (!HeadlessInAppWebView.isClassSupported()) {
      _logWebView('unsupported selectedId=$selectedId');
      return null;
    }

    final controllerReady = Completer<InAppWebViewController>();
    InAppWebViewController? controller;
    var runAttempted = false;
    final headlessWebView = HeadlessInAppWebView(
      initialSize: const Size(1280, 800),
      initialUrlRequest: URLRequest(
        url: WebUri(pageUri.toString()),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
        preferredContentMode: UserPreferredContentMode.DESKTOP,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        supportZoom: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        blockNetworkImage: false,
        loadsImagesAutomatically: true,
        mediaPlaybackRequiresUserGesture: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        disableContextMenu: true,
        horizontalScrollBarEnabled: false,
        verticalScrollBarEnabled: false,
        allowFileAccess: false,
        allowContentAccess: false,
        geolocationEnabled: false,
        isInspectable: false,
        contentBlockers: [
          ContentBlocker(
            trigger: ContentBlockerTrigger(
              urlFilter: '.*',
              resourceType: [
                ContentBlockerTriggerResourceType.IMAGE,
              ],
              unlessDomain: [
                '*google.com',
                '*gstatic.com',
                '*googleusercontent.com',
              ],
            ),
            action: ContentBlockerAction(
              type: ContentBlockerActionType.BLOCK,
            ),
          ),
        ],
      ),
      onWebViewCreated: (createdController) {
        if (!controllerReady.isCompleted) {
          controllerReady.complete(createdController);
        }
      },
    );

    try {
      await FaRequestCoordinator.instance.waitForTurn(
        label: 'HEADLESS GET ${pageUri.origin}${pageUri.path}',
      );
      _logWebView('start selectedId=$selectedId');
      runAttempted = true;
      await headlessWebView.run();
      final activeController = await controllerReady.future.timeout(
        const Duration(seconds: 4),
      );
      controller = activeController;
      final script = _buildImageUrlLookupScript(selectedId);
      final deadline = DateTime.now().add(_timeout);
      while (DateTime.now().isBefore(deadline)) {
        try {
          final value = await activeController.evaluateJavascript(
            source: script,
          );
          final imageUrl = _httpImageUrl(value);
          if (imageUrl != null) {
            _logWebView(
              'resolved selectedId=$selectedId image=$imageUrl',
            );
            return imageUrl;
          }
        } catch (_) {}
        await Future<void>.delayed(_pollInterval);
      }
      _logWebView('timeout selectedId=$selectedId');
      return null;
    } finally {
      final disposeTimer = Stopwatch()..start();
      var stillRunning = runAttempted;
      final activeController = controller;
      if (activeController != null) {
        try {
          await activeController
              .stopLoading()
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      if (runAttempted) {
        try {
          await headlessWebView.dispose();
        } catch (error, stackTrace) {
          _logWebViewError(
            'dispose exception selectedId=$selectedId',
            error,
            stackTrace,
          );
        }
      }
      try {
        stillRunning = headlessWebView.isRunning();
      } catch (_) {}
      disposeTimer.stop();
      _logWebView(
        'dispose finished selectedId=$selectedId '
        'stillRunning=$stillRunning '
        'after=${disposeTimer.elapsedMilliseconds}ms',
      );
    }
  }
}

String _buildImageUrlLookupScript(String selectedId) {
  final encodedSelectedId = jsonEncode(selectedId);
  return '''
(() => {
  const selectedId = $encodedSelectedId;
  const stateKey = '__faNoteImagePreviewResolver';
  const existing = window[stateKey];
  if (existing && existing.selectedId === selectedId) {
    existing.install();
    return existing.value;
  }
  const accept = (value) => {
    if (typeof value !== 'string' || value.length === 0) return null;
    let parsed;
    try {
      parsed = new URL(value, location.href);
    } catch (_) {
      return null;
    }
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null;
    }
    const lower = parsed.href.toLowerCase();
    if (lower.includes('encrypted-tbn') ||
        lower.includes('images?q=tbn:')) {
      return null;
    }
    return parsed.href;
  };
  const selectors = [
    'img[jsname="kn3ccd"].sFlh5c[src]',
    'img[jsname="kn3ccd"][src]',
    'img.sFlh5c.iPVvYb[src]'
  ];
  const fromSource = (source) => {
    const marker = '[0,"' + selectedId + '",["';
    const blockStart = source.indexOf(marker);
    if (blockStart < 0) return null;
    const imageStartMarker = '],["';
    const imageBlockStart = source.indexOf(
      imageStartMarker,
      blockStart + marker.length
    );
    if (imageBlockStart < 0) return null;
    const urlStart = imageBlockStart + imageStartMarker.length;
    let urlEnd = urlStart;
    while (urlEnd < source.length) {
      if (source.charAt(urlEnd) === '"' &&
          source.charCodeAt(urlEnd - 1) !== 92) {
        break;
      }
      urlEnd++;
    }
    if (urlEnd >= source.length) return null;
    const raw = source.substring(urlStart, urlEnd);
    let decoded = raw;
    try {
      decoded = JSON.parse(
        String.fromCharCode(34) + raw + String.fromCharCode(34)
      );
    } catch (_) {}
    return accept(decoded);
  };
  const scan = () => {
    for (const selector of selectors) {
      for (const image of document.querySelectorAll(selector)) {
        for (const source of [
          image.getAttribute('src'),
          image.currentSrc,
          image.src
        ]) {
          const accepted = accept(source);
          if (accepted) return accepted;
        }
      }
    }
    for (const script of document.scripts) {
      const accepted = fromSource(script.textContent || '');
      if (accepted) return accepted;
    }
    return null;
  };
  const state = {
    selectedId,
    value: null,
    observer: null,
    scheduled: false,
    install: null
  };
  const update = () => {
    if (state.value) return;
    state.value = scan();
    if (state.value && state.observer) {
      state.observer.disconnect();
      state.observer = null;
    }
  };
  state.install = () => {
    if (state.observer || state.value || !document.documentElement) return;
    state.observer = new MutationObserver(() => {
      if (state.value || state.scheduled) return;
      state.scheduled = true;
      setTimeout(() => {
        state.scheduled = false;
        update();
      }, 40);
    });
    state.observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: ['src']
    });
    update();
  };
  window[stateKey] = state;
  state.install();
  return state.value;
})()
''';
}

String? _httpImageUrl(dynamic value) {
  if (value is! String) return null;
  var candidate = value.trim();
  if (candidate.isEmpty) return null;
  if (candidate.startsWith('"') && candidate.endsWith('"')) {
    candidate = _decodeQuotedCandidate(candidate);
  }
  final uri = Uri.tryParse(candidate);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final lower = uri.toString().toLowerCase();
  if (lower.contains('encrypted-tbn') ||
      lower.contains('images?q=tbn:')) {
    return null;
  }
  return uri.removeFragment().toString();
}

String _decodeQuotedCandidate(String candidate) {
  try {
    final decoded = jsonDecode(candidate);
    return decoded is String ? decoded : candidate;
  } on FormatException {
    return candidate;
  }
}

void _logWebView(String message) {
  if (!kDebugMode) {
    return;
  }
  debugPrint('[Note image preview WebView] $message');
}

void _logWebViewError(
  String message,
  Object error,
  StackTrace stackTrace,
) {
  if (!kDebugMode) {
    return;
  }
  debugPrint('[Note image preview WebView] $message error=$error');
  debugPrintStack(
    label: '[Note image preview WebView] stack trace',
    stackTrace: stackTrace,
  );
}
