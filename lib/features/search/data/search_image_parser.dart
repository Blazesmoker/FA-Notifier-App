import 'package:FANotifier/core/logging/app_logging.dart';
import 'package:FANotifier/shared/fa/fa_thumbnail_processing.dart';

Future<List<Map<String, dynamic>>> parseSearchImageHtml(String html) async {
  final imageMetadata = await parseFaThumbnailHtml(html);
  kDebugPrint(
    '[Search] HTML parser found ${imageMetadata.length} usable thumbnails.',
  );
  return imageMetadata;
}
