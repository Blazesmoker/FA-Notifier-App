import 'dart:typed_data';

import 'package:fanotifier/core/media/domain/media_bytes_repository.dart';

class SubmissionImageService {
  const SubmissionImageService({required this._mediaBytesRepository});

  final MediaBytesRepository _mediaBytesRepository;

  Future<Uint8List?> fetchImageBytes(String imageUrl) async {
    final response = await _mediaBytesRepository.load(
      imageUrl,
      purpose: MediaLoadPurpose.download,
    );
    if (response.statusCode != 200) {
      return null;
    }
    return response.bytes;
  }
}
