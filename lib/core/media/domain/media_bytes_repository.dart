import 'dart:typed_data';

enum MediaLoadPurpose { display, download }

class MediaBytesData {
  const MediaBytesData({
    required this.bytes,
    required this.statusCode,
    this.contentType,
  });

  final Uint8List bytes;
  final int statusCode;
  final String? contentType;
}

abstract interface class MediaBytesRepository {
  void evict(String url);

  Future<MediaBytesData> load(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
    MediaLoadPurpose purpose = MediaLoadPurpose.display,
    void Function(int loaded, int? total)? onBytesReceived,
  });
}
