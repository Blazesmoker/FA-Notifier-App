import 'package:html/dom.dart' as dom;

import 'package:FANotifier/features/settings/domain/tag_blocklist_parse_result.dart';

class TagBlocklistApiService {
  static TagBlocklistParseResult parse(dom.Document document, String rawHtml) {
    dom.Element? tagSection;
    for (final section in document.querySelectorAll('section')) {
      final h2 =
          section.querySelector('.section-header h2') ?? section.querySelector('h2');
      if (h2 == null) continue;
      if (h2.text.trim().toLowerCase() == 'tag block list') {
        tagSection = section;
        break;
      }
    }
    tagSection ??= document.querySelector('section');

    String? nonce =
        document.querySelector('body')?.attributes['data-tag-blocklist-nonce']?.trim();
    if (nonce == null || nonce.isEmpty) {
      nonce = RegExp(r'data-tag-blocklist-nonce\s*=\s*"([^"]+)"',
              caseSensitive: false)
          .firstMatch(rawHtml)
          ?.group(1)
          ?.trim();
    }

    final blocked = <String>{};

    final bodyRaw = document.querySelector('body')?.attributes['data-tag-blocklist'] ?? '';
    if (bodyRaw.trim().isNotEmpty) {
      blocked.addAll(
        bodyRaw
            .trim()
            .split(RegExp(r'\s+'))
            .where((t) => t.trim().isNotEmpty)
            .map((t) => t.trim().toLowerCase()),
      );
    }

    final scope = tagSection ?? document;
    for (final el
        in scope.querySelectorAll('a.tag-block.remove-tag[data-tag-name]')) {
      final name = el.attributes['data-tag-name']?.trim().toLowerCase();
      if (name != null && name.isNotEmpty) blocked.add(name);
    }

    int? total;
    final totalText = scope.querySelector('#tag-blocklist-total')?.text.trim();
    if (totalText != null && totalText.isNotEmpty) {
      total = int.tryParse(totalText);
    }

    final blockedTags = blocked.toList()..sort();

    return TagBlocklistParseResult(
      blockedTags: blockedTags,
      total: total,
      nonce: (nonce != null && nonce.isNotEmpty) ? nonce : null,
    );
  }
}
