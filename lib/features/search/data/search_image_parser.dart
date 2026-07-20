import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/shared/fa/fa_thumbnail_processing.dart';

Future<List<Map<String, dynamic>>> parseSearchImageHtml(String html) async {
  final imageMetadata = await parseFaThumbnailHtml(html);
  kDebugPrint(
    '[Search] HTML parser found ${imageMetadata.length} usable thumbnails.',
  );
  return imageMetadata;
}
