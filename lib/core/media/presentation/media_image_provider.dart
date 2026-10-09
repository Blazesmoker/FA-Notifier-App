import 'dart:async';
import 'dart:ui' as ui;

import 'package:fanotifier/core/media/domain/media_bytes_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

class MediaImageProvider extends ImageProvider<MediaImageProvider> {
  MediaImageProvider({
    required this.url,
    required this.repository,
    required this.sessionRevision,
    Map<String, String>? headers,
  }) : headers = Map<String, String>.unmodifiable(headers ?? {});

  final String url;
  final MediaBytesRepository repository;
  final int sessionRevision;
  final Map<String, String> headers;

  @override
  Future<MediaImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<MediaImageProvider>(this);
  }

  @override
  Future<bool> evict({
    ImageCache? cache,
    ImageConfiguration configuration = ImageConfiguration.empty,
  }) {
    repository.evict(url);
    return super.evict(cache: cache, configuration: configuration);
  }

  @override
  ImageStreamCompleter loadImage(
    MediaImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunks = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode, chunks),
      scale: 1,
      chunkEvents: chunks.stream,
    );
  }

  Future<ui.Codec> _load(
    MediaImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunks,
  ) async {
    try {
      chunks.add(const ImageChunkEvent(
        cumulativeBytesLoaded: 0,
        expectedTotalBytes: null,
      ));
      final data = await repository.load(
        url,
        headers: headers,
        timeout: Duration.zero,
        purpose: MediaLoadPurpose.display,
        onBytesReceived: (loaded, total) {
          if (chunks.isClosed) {
            return;
          }
          chunks.add(ImageChunkEvent(
            cumulativeBytesLoaded: loaded,
            expectedTotalBytes: total,
          ));
        },
      );
      if (data.statusCode != 200) {
        throw NetworkImageLoadException(
          statusCode: data.statusCode,
          uri: Uri.parse(url),
        );
      }
      if (data.bytes.isEmpty) {
        throw StateError('Empty image');
      }
      return await decode(await ui.ImmutableBuffer.fromUint8List(data.bytes));
    } catch (_) {
      repository.evict(url);
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    } finally {
      unawaited(chunks.close());
    }
  }

  @override
  bool operator ==(Object other) {
    return other is MediaImageProvider &&
        url == other.url &&
        identical(repository, other.repository) &&
        sessionRevision == other.sessionRevision &&
        mapEquals(headers, other.headers);
  }

  @override
  int get hashCode {
    final names = headers.keys.toList()..sort();
    return Object.hash(
      url,
      repository,
      sessionRevision,
      Object.hashAll(names.map((name) => Object.hash(name, headers[name]))),
    );
  }
}
