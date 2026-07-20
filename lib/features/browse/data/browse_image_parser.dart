import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/shared/fa/fa_thumbnail_processing.dart';

Future<List<Map<String, dynamic>>> parseBrowseImageHtml(String html) async {
  final imageMetadata = await parseFaThumbnailHtml(html);
  kDebugPrint(
    '[Browse] HTML parser found ${imageMetadata.length} usable thumbnails.',
  );
  return imageMetadata;
}
