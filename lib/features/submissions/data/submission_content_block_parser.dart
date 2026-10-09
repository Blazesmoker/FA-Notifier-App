import 'package:html/dom.dart' as dom;

import 'package:fanotifier/features/submissions/data/submission_metadata_parser.dart';
import 'package:fanotifier/shared/fa/data/fa_content_block_parser.dart';
import 'package:fanotifier/shared/fa/domain/fa_content_block_data.dart';

FaContentBlockData parseSubmissionContentBlockData(dom.Document document) {
  final image = document.querySelector('img#submissionImg');
  final snapshot = parseFaContentBlockSnapshot(document);
  if (image == null || image.attributes.containsKey('data-tags')) {
    return parseFaContentBlockData(image, snapshot: snapshot);
  }
  final metadata = parseSubmissionMetadata(document);
  return parseFaContentBlockData(
    image,
    snapshot: snapshot,
    fallbackTags: [
      for (final tag in metadata.keywordTags) tag.name,
      for (final tag in metadata.metaKeywordTags) tag.name,
    ],
  );
}
