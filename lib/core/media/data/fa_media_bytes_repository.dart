import 'dart:async';

import 'package:fanotifier/core/fa/fa_media_auth.dart';
import 'package:fanotifier/core/media/domain/media_bytes_repository.dart';
import 'package:fanotifier/core/network/fa_http.dart';

class FaMediaBytesRepository implements MediaBytesRepository {
  FaMediaBytesRepository() {
    FaMediaAuth.changes.addListener(_resetSession);
  }

  static const int _maximumBytes = 32 * 1024 * 1024;
  static const int _maximumEntries = 128;

  final Map<_MediaBytesKey, MediaBytesData> _cache = {};
  final Map<_MediaBytesKey, _MediaBytesRequest> _inFlight = {};
  int _cachedBytes = 0;
  int _sessionRevision = FaMediaAuth.changes.value;

  void _resetSession() {
    _sessionRevision = FaMediaAuth.changes.value;
    _cache.clear();
    _inFlight.clear();
    _cachedBytes = 0;
  }

  @override
  void evict(String url) {
    final resolvedUrl = FaMediaAuth.normalizeUrl(url);
    final cachedKeys = _cache.keys
        .where((key) => key.url == resolvedUrl)
        .toList();
    for (final key in cachedKeys) {
      _cachedBytes -= _cache.remove(key)!.bytes.lengthInBytes;
    }
    _inFlight.removeWhere((key, _) => key.url == resolvedUrl);
  }

  @override
  Future<MediaBytesData> load(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
    MediaLoadPurpose purpose = MediaLoadPurpose.display,
    void Function(int loaded, int? total)? onBytesReceived,
  }) async {
    final revision = _sessionRevision;
    final resolvedUrl = FaMediaAuth.normalizeUrl(url);
    final requestHeaders = headers ?? await FaMediaAuth.headersForUrl(resolvedUrl);
    if (revision != _sessionRevision) {
      throw StateError('Media session changed');
    }
    final key = _MediaBytesKey(resolvedUrl, requestHeaders, revision);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final pending = _inFlight[key];
    if (pending != null) {
      pending.addProgressListener(onBytesReceived);
      if (purpose == MediaLoadPurpose.display) {
        pending.useForDisplay();
      }
      return pending.result;
    }

    final request = _MediaBytesRequest(purpose);
    request.addProgressListener(onBytesReceived);
    request.result = _load(
      key,
      headers: requestHeaders,
      timeout: timeout,
      request: request,
    ).then((result) {
      if (identical(_inFlight[key], request)) {
        _remember(key, result);
      }
      return result;
    }).whenComplete(() {
      if (identical(_inFlight[key], request)) {
        _inFlight.remove(key);
      }
    });
    _inFlight[key] = request;
    return request.result;
  }

  Future<MediaBytesData> _load(
    _MediaBytesKey key, {
    required Map<String, String>? headers,
    required Duration? timeout,
    required _MediaBytesRequest request,
  }) async {
    final response = await FAHttp.getMedia(
      Uri.parse(key.url),
      headers: headers,
      timeout: timeout,
      queueFaRequest: request.queueFaRequest,
      bypassQueue: request.displayRequested,
      isCancelled: () => key.revision != _sessionRevision,
      onBytesReceived: request.notifyBytesReceived,
    );
    if (key.revision != _sessionRevision) {
      throw StateError('Media session changed');
    }
    return MediaBytesData(
      bytes: response.bodyBytes,
      statusCode: response.statusCode,
      contentType: response.headers['content-type'],
    );
  }

  void _remember(_MediaBytesKey key, MediaBytesData result) {
    final length = result.bytes.lengthInBytes;
    if (result.statusCode == 200 &&
        length > 0 &&
        length <= _maximumBytes &&
        !(result.contentType ?? '').toLowerCase().contains('html')) {
      while (_cache.isNotEmpty &&
          (_cachedBytes + length > _maximumBytes ||
              _cache.length >= _maximumEntries)) {
        _cachedBytes -= _cache.remove(_cache.keys.first)!.bytes.lengthInBytes;
      }
      _cache[key] = result;
      _cachedBytes += length;
    }
  }
}

class _MediaBytesRequest {
  _MediaBytesRequest(MediaLoadPurpose purpose) {
    if (purpose == MediaLoadPurpose.display) {
      useForDisplay();
    }
  }

  final Completer<void> _displayRequested = Completer<void>();
  final Set<void Function(int, int?)> _progressListeners = {};
  late final Future<MediaBytesData> result;

  bool get queueFaRequest => !_displayRequested.isCompleted;
  Future<void> get displayRequested => _displayRequested.future;

  void useForDisplay() {
    if (!_displayRequested.isCompleted) {
      _displayRequested.complete();
    }
  }

  void addProgressListener(void Function(int, int?)? listener) {
    if (listener != null) {
      _progressListeners.add(listener);
    }
  }

  void notifyBytesReceived(int loaded, int? total) {
    for (final listener in _progressListeners.toList(growable: false)) {
      listener(loaded, total);
    }
  }
}

class _MediaBytesKey {
  _MediaBytesKey(this.url, Map<String, String>? headers, this.revision)
      : headerEntries = (headers?.entries
                .map((entry) => (entry.key.toLowerCase(), entry.value))
                .toList() ??
            <(String, String)>[])
          ..sort((a, b) => a.$1.compareTo(b.$1));

  final String url;
  final int revision;
  final List<(String, String)> headerEntries;

  @override
  bool operator ==(Object other) {
    if (other is! _MediaBytesKey ||
        url != other.url ||
        revision != other.revision ||
        headerEntries.length != other.headerEntries.length) {
      return false;
    }
    for (var index = 0; index < headerEntries.length; index++) {
      if (headerEntries[index] != other.headerEntries[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(url, revision, Object.hashAll(headerEntries));
}
