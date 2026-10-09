import 'package:html/dom.dart' as dom;

import 'package:fanotifier/shared/fa/domain/fa_content_block_data.dart';

FaContentBlockSnapshot? parseFaContentBlockSnapshot(dom.Document document) {
  final body = document.body;
  if (body == null ||
      body.attributes['data-user-logged-in'] == '0' ||
      !body.attributes.containsKey('data-tag-blocklist')) {
    return null;
  }
  return FaContentBlockSnapshot(
    blockedTags: Set<String>.unmodifiable(
      _splitTags(body.attributes['data-tag-blocklist'] ?? ''),
    ),
  );
}

FaContentBlockData parseFaContentBlockData(
  dom.Element? element, {
  required FaContentBlockSnapshot? snapshot,
  Iterable<String>? fallbackTags,
}) {
  final rawTags = element?.attributes['data-tags'];
  final tags = rawTags != null
      ? _splitTags(rawTags)
      : fallbackTags
          ?.map((tag) => tag.trim().toLowerCase())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList(growable: false);
  return FaContentBlockData(
    tags: List<String>.unmodifiable(tags ?? const <String>[]),
    tagsKnown: rawTags != null || fallbackTags != null,
    snapshot: snapshot,
  );
}

List<String> _splitTags(String raw) {
  return raw
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
