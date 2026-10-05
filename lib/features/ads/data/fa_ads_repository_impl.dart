import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:fanotifier/core/logging/fa_ads_logging.dart';
import 'package:fanotifier/features/ads/data/fa_ad_image_metadata.dart';
import 'package:fanotifier/features/ads/data/fa_ad_parser.dart';
import 'package:fanotifier/features/ads/data/fa_ad_transport.dart';
import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/features/ads/domain/fa_ads_repository.dart';

class FaAdsRepositoryImpl implements FaAdsRepository {
  FaAdsRepositoryImpl({FaAdTransport? transport})
      : _transport = transport ?? FaAdTransport();

  final FaAdTransport _transport;
  final LinkedHashMap<Uri, _CachedAdImage> _images = LinkedHashMap();
  int _cachedBytes = 0;

  @override
  Future<void> acceptDocumentCookies({
    required Uri documentUri,
    required String? setCookieHeader,
  }) => _transport.acceptDocumentCookies(
        documentUri: documentUri,
        setCookieHeader: setCookieHeader,
      );

  @override
  Future<FaAdDelivery> fetchDelivery({
    required FaAdPageMetadata page,
    required FaAdLayout layout,
    required FaAdCancellation cancellation,
    required bool Function() canStart,
  }) async {
    final loc = _encodeWebsiteUri(page.documentUri.toString());
    final uri = Uri.parse('${page.deliveryUri}?zones=${layout.zones.join('|')}'
        '&r=${DateTime.now().millisecondsSinceEpoch}&loc=$loc');
    final response = await _transport.get(
      uri: uri, page: page, kind: FaAdRequestKind.delivery,
      cancellation: cancellation, canStart: canStart,
    );
    if (response.status != 200) throw const FaAdFailure(FaAdFailureReason.http);
    if (!response.text.contains('OA_output')) {
      throw const FaAdFailure(FaAdFailureReason.invalidResponse);
    }
    final delivery = parseFaAdDelivery(response.text, layout);
    FaAdsLog.event(FaAdsLogCategory.delivery, 'batch_parsed',
        counts: {'zones': layout.zones.length, 'creatives': delivery.creatives.length,
          'fetchOnlyZones': layout.fetchOnlyZones.length},
        checks: {'scriptExecuted': false, 'locFromPage': true, 'queryRefererAdded': false});
    return delivery;
  }

  @override
  Future<FaAdImage> fetchImage({
    required FaAdCreative creative,
    required FaAdPageMetadata page,
    required FaAdCancellation cancellation,
  }) async {
    if (cancellation.isCancelled) throw const FaAdFailure(FaAdFailureReason.cancelled);
    final cached = _images.remove(creative.imageUri);
    if (cached != null) {
      if (cached.expires.isAfter(DateTime.now())) {
        _images[creative.imageUri] = cached;
        FaAdsLog.event(FaAdsLogCategory.http, 'image_cache_hit',
            checks: {'countingRequestCached': false});
        final image = await _prepareImage(
          cached.bytes, creative, cancellation, cached.intrinsicSize,
        );
        cached.intrinsicSize = image.intrinsicSize;
        return image;
      }
      _cachedBytes -= cached.bytes.length;
    }
    final response = await _transport.get(
      uri: creative.imageUri, page: page, kind: FaAdRequestKind.image,
      cancellation: cancellation,
    );
    if (response.status != 200 || response.bytes.isEmpty) {
      throw const FaAdFailure(FaAdFailureReason.http);
    }
    final image = await _prepareImage(response.bytes, creative, cancellation, null);
    final cacheControl = response.headers.value(HttpHeaders.cacheControlHeader) ?? '';
    final maxAge = int.tryParse(RegExp(r'max-age=(\d+)').firstMatch(cacheControl)?.group(1) ?? '');
    if (cacheControl.contains('public') && !cacheControl.contains('no-store') &&
        !cacheControl.contains('no-cache') && maxAge != null && maxAge > 0 &&
        response.bytes.length <= 8 * 1024 * 1024) {
      final replaced = _images.remove(creative.imageUri);
      if (replaced != null) _cachedBytes -= replaced.bytes.length;
      _images[creative.imageUri] = _CachedAdImage(
        response.bytes, DateTime.now().add(Duration(seconds: maxAge)),
        intrinsicSize: image.intrinsicSize,
      );
      _cachedBytes += response.bytes.length;
      while (_images.length > 24 || _cachedBytes > 8 * 1024 * 1024) {
        _cachedBytes -= _images.remove(_images.keys.first)!.bytes.length;
      }
    }
    return image;
  }

  Future<FaAdImage> _prepareImage(
    Uint8List bytes, FaAdCreative creative,
    FaAdCancellation cancellation, FaAdSize? cachedSize,
  ) async {
    if (cancellation.isCancelled) throw const FaAdFailure(FaAdFailureReason.cancelled);
    var intrinsicSize = cachedSize;
    if (creative.declaredSize == null && intrinsicSize == null) {
      intrinsicSize = await readFaAdImageSize(bytes);
      FaAdsLog.event(FaAdsLogCategory.config, 'image_intrinsic_size_read',
          counts: {'intrinsicWidth': intrinsicSize.width,
            'intrinsicHeight': intrinsicSize.height},
          checks: {'extraHttpRequest': false, 'animationFramesDecoded': false});
    }
    if (cancellation.isCancelled) throw const FaAdFailure(FaAdFailureReason.cancelled);
    return FaAdImage(bytes: bytes, intrinsicSize: intrinsicSize);
  }

  @override
  Future<void> registerImpression({
    required FaAdCreative creative,
    required FaAdPageMetadata page,
    required FaAdCancellation cancellation,
    required bool Function() canStart,
  }) async {
    final response = await _transport.get(
      uri: creative.impressionUri, page: page, kind: FaAdRequestKind.impression,
      cancellation: cancellation, canStart: canStart,
    );
    if (response.status != 200) throw const FaAdFailure(FaAdFailureReason.http);
    if (response.bytes.length < 6 ||
        String.fromCharCodes(response.bytes.take(6)) != 'GIF89a' &&
            String.fromCharCodes(response.bytes.take(6)) != 'GIF87a') {
      throw const FaAdFailure(FaAdFailureReason.invalidResponse);
    }
  }

  @override
  Future<Uri> resolveClick({
    required FaAdCreative creative,
    required FaAdPageMetadata page,
    required FaAdCancellation cancellation,
    required bool Function() canStart,
  }) => resolveClickUrl(
        clickUri: creative.clickUri,
        page: page,
        cancellation: cancellation,
        canStart: canStart,
      );

  @override
  Future<Uri> resolveClickUrl({
    required Uri clickUri,
    required FaAdPageContext page,
    required FaAdCancellation cancellation,
    required bool Function() canStart,
  }) async {
    var current = clickUri;
    var referrer = faAdReferrer(page.documentUri, current);
    final seen = <String>{};
    for (var hop = 0; hop < 5; hop++) {
      if (!seen.add(current.toString()) ||
          !(isFaAdEndpoint(current, 'cl.php') || isFaAdEndpoint(current, 'ck.php'))) {
        throw const FaAdFailure(FaAdFailureReason.invalidResponse);
      }
      final response = await _transport.get(
        uri: current, page: page, kind: FaAdRequestKind.click,
        cancellation: cancellation, canStart: canStart, referrer: referrer,
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (![301, 302, 303, 307, 308].contains(response.status) ||
          location == null || location.isEmpty) {
        throw const FaAdFailure(FaAdFailureReason.invalidResponse);
      }
      final next = current.resolve(location);
      if ((next.scheme != 'https' && next.scheme != 'http') ||
          next.host.isEmpty || next.userInfo.isNotEmpty) {
        throw const FaAdFailure(FaAdFailureReason.invalidResponse);
      }
      final policy = response.headers.value('referrer-policy')?.split(',').last.trim();
      if (policy == 'no-referrer' || policy == 'same-origin' && current.origin != next.origin ||
          current.scheme == 'https' && next.scheme != 'https') {
        referrer = '';
      } else if (referrer.isNotEmpty) {
        referrer = faAdReferrer(Uri.parse(referrer), next);
      }
      final tracking = isFaAdEndpoint(next, 'cl.php') || isFaAdEndpoint(next, 'ck.php');
      FaAdsLog.event(FaAdsLogCategory.click, 'redirect_resolved',
          counts: {'hop': hop + 1, 'status': response.status},
          checks: {'trackingHop': tracking, 'finalContentFetched': false,
            'serverDestinationUsed': true});
      if (!tracking) return next;
      current = next;
    }
    throw const FaAdFailure(FaAdFailureReason.invalidResponse);
  }

  @override
  Future<void> resetSession() {
    _images.clear();
    _cachedBytes = 0;
    return _transport.resetSession();
  }

  @override
  void dispose() {
    _images.clear();
    _cachedBytes = 0;
    _transport.dispose();
  }
}

class _CachedAdImage {
  _CachedAdImage(this.bytes, this.expires, {this.intrinsicSize});

  final Uint8List bytes;
  final DateTime expires;
  FaAdSize? intrinsicSize;
}

String _encodeWebsiteUri(String value) {
  final encoded = StringBuffer();
  const safe = ";,/?:@&=+\$-_.!~*'()#";
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (RegExp(r'^[a-zA-Z0-9]$').hasMatch(char) || safe.contains(char)) {
      encoded.write(char);
    } else {
      encoded.write(Uri.encodeComponent(char));
    }
  }
  return encoded.toString();
}
