import 'package:html/dom.dart' as dom;

import 'package:fanotifier/features/submissions/domain/submission_document_models.dart';
import 'package:fanotifier/shared/fa/parsing_utils.dart';

List<SubmissionFolderLink> parseSubmissionFolderLinks(dom.Document document) {
  final folders = <SubmissionFolderLink>[];
  final seenUrls = <String>{};

  for (final anchor in document.querySelectorAll(
    '.folder-list-container .submission-folder a[href], '
    '#submission-sidebar-lower .submission-folder a[href]',
  )) {
    final url = normalizeFaUrl(anchor.attributes['href']);
    if (url == null) continue;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !RegExp(r'^/gallery/[^/]+/folder/\d+/[^/]+/?$')
            .hasMatch(uri.path) ||
        !seenUrls.add(url)) {
      continue;
    }

    final folderName = anchor.querySelector('span')?.text.trim() ?? '';
    final groupName = anchor.querySelector('strong')?.text.trim() ?? '';
    final hasGroupName = groupName
        .replaceAll(RegExp(r'[\s\-\u2013\u2014]'), '')
        .isNotEmpty;
    final name = folderName.isNotEmpty
        ? hasGroupName
            ? '$groupName -- $folderName'
            : folderName
        : anchor.text.trim();
    if (name.isEmpty) continue;

    folders.add(SubmissionFolderLink(name: name, url: url));
  }

  return List<SubmissionFolderLink>.unmodifiable(folders);
}
