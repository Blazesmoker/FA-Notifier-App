import 'dart:convert';

import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';

String buildFaWebViewAdTapHandlerScript({
  required String documentPathPattern,
}) {
  final pathPattern = jsonEncode(documentPathPattern);
  final placements = jsonEncode(
    FaAdPlacement.values.map((placement) => placement.websiteId).toList(),
  );
  return '''
(function() {
  if (window !== window.top || window.__faWebViewAdTapHandlerInstalled) return;
  if (window.location.origin !== 'https://www.furaffinity.net' &&
      window.location.origin !== 'https://furaffinity.net') return;
  if (!(new RegExp($pathPattern)).test(window.location.pathname)) return;

  window.__faWebViewAdTapHandlerInstalled = true;
  var placements = $placements;
  var pending = false;

  document.addEventListener('click', function(event) {
    if (!event.isTrusted || event.defaultPrevented || event.button !== 0) return;
    var target = event.target;
    if (!target || typeof target.closest !== 'function') return;
    var anchor = target.closest('a[href]');
    if (!anchor) return;
    var slot = anchor.closest('.jsAdSlot[data-id]');
    if (!slot || !slot.closest('.leaderboardAd, .footerAds')) return;
    var placement = slot.getAttribute('data-id');
    if (placements.indexOf(placement) === -1) return;
    var image = anchor.querySelector('img');
    if (!image || !image.complete || image.naturalWidth <= 0) return;
    var bridge = window.flutter_inappwebview;
    if (!bridge || typeof bridge.callHandler !== 'function') return;
    var href = anchor.href;
    if (!href || !/^https?:/.test(href)) return;

    event.preventDefault();
    if (pending) return;
    pending = true;
    bridge.callHandler('faWebViewAdTap', {href: href, placement: placement})
      .catch(function() {})
      .then(function() { pending = false; });
  }, true);
})();
''';
}
