import 'package:fanotifier/core/media/data/fa_media_bytes_repository.dart';
import 'package:fanotifier/core/media/domain/media_bytes_repository.dart';

class MediaFeature {
  MediaFeature._();

  static final MediaBytesRepository bytesRepository = FaMediaBytesRepository();
}
