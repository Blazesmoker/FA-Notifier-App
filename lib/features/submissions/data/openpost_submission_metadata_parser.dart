import 'package:html/dom.dart' as dom;

import 'package:FANotifier/core/utils/html_tags_debug.dart';
import 'package:FANotifier/features/submissions/domain/openpost_models.dart';
import 'package:FANotifier/features/submissions/domain/openpost_parse_sections.dart';

OpenPostSubmissionMetadata parseOpenPostSubmissionMetadata(
  dom.Document document,
) {
  final infoSection = logQuery(
    document,
    'section.info.text, .submission-content-stats, td.alt1.stats-container',
  );
  String? category;
  String? type;
  String? species;
  String? gender;
  String? size;
  String? fileSize;
  final isClassic = document
          .querySelector('body')
          ?.attributes['data-static-path']
          ?.contains('themes/classic') ??
      false;

  if (infoSection != null) {
    if (infoSection.classes.contains('submission-content-stats')) {
      final spans = infoSection.children
          .where((element) => element.localName == 'span')
          .toList();
      if (spans.length >= 2) {
        final labels = spans[0]
            .children
            .map((element) => element.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
        final values = spans[1]
            .children
            .map((element) => element.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
        for (var index = 0;
            index < labels.length && index < values.length;
            index++) {
          final label = labels[index];
          final value = values[index];
          switch (label) {
            case 'Category':
              final parts = value.split('/').map((part) => part.trim()).toList();
              category = parts.isNotEmpty ? parts.first : value;
              if (parts.length > 1) type = parts.sublist(1).join(' / ');
              break;
            case 'Sub-Category':
            case 'Theme':
            case 'Type':
              type = value;
              break;
            case 'Species':
              species = value;
              break;
            case 'Gender':
              gender = value;
              break;
            case 'Resolution':
            case 'Size':
              size = value;
              break;
            case 'File Size':
              fileSize = value;
              break;
          }
        }
      }
    } else if (!isClassic) {
      final divs = infoSection.querySelectorAll('div');
      for (final div in divs) {
        final strong = div.querySelector('strong.highlight');
        if (strong == null) continue;
        final label = strong.text.trim();
        switch (label) {
          case 'Category':
            category = div.querySelector('.category-name')?.text.trim();
            type ??= div.querySelector('.type-name')?.text.trim();
            break;
          case 'Theme':
          case 'Type':
            type = div.querySelector('.type-name')?.text.trim() ??
                div.querySelector('.theme-name')?.text.trim() ??
                div.querySelector('span')?.text.trim();
            break;
          case 'Species':
            species = div.querySelector('span')?.text.trim();
            break;
          case 'Gender':
            gender = div.querySelector('span')?.text.trim();
            break;
          case 'Size':
            size = div.querySelector('span')?.text.trim();
            break;
          case 'File Size':
            fileSize = div.querySelector('span')?.text.trim();
            break;
        }
      }
    } else {
      final infoHtml = infoSection.innerHtml;
      category ??= RegExp(
        r'<b>\s*Category:\s*</b>\s*([^<]+)<br\s*/?>',
        caseSensitive: false,
      ).firstMatch(infoHtml)?.group(1)?.trim();
      type ??= RegExp(
        r'<b>\s*Theme:\s*</b>\s*([^<]+)<br\s*/?>',
        caseSensitive: false,
      ).firstMatch(infoHtml)?.group(1)?.trim();
      species ??= RegExp(
        r'<b>\s*Species:\s*</b>\s*([^<]+)<br\s*/?>',
        caseSensitive: false,
      ).firstMatch(infoHtml)?.group(1)?.trim();
      gender ??= RegExp(
        r'<b>\s*Gender:\s*</b>\s*([^<]+)<br\s*/?>',
        caseSensitive: false,
      ).firstMatch(infoHtml)?.group(1)?.trim();
      final sizeMatch = RegExp(
        r'<b>\s*Resolution:\s*</b>\s*([0-9]+)\s*x\s*([0-9]+)<br\s*/?>',
        caseSensitive: false,
      ).firstMatch(infoHtml);
      if (sizeMatch != null) {
        size = '${sizeMatch.group(1)?.trim()} x ${sizeMatch.group(2)?.trim()}';
      }
      fileSize ??= RegExp(
        r'<b>\s*File Size:\s*</b>\s*([^<]+)<br\s*/?>',
        caseSensitive: false,
      ).firstMatch(infoHtml)?.group(1)?.trim();
    }
  }

  double? imageWidth;
  double? imageHeight;
  if (infoSection != null) {
    if (infoSection.classes.contains('submission-content-stats')) {
      final sizeText = size;
      if (sizeText != null) {
        final dimensions = sizeText.toLowerCase().split('x');
        if (dimensions.length >= 2) {
          imageWidth = double.tryParse(dimensions[0].trim());
          imageHeight = double.tryParse(dimensions[1].trim());
        }
      }
    } else if (!isClassic) {
      final divs = infoSection.querySelectorAll('div');
      for (final div in divs) {
        final strong = div.querySelector('strong.highlight');
        if (strong != null && strong.text.trim() == 'Size') {
          final sizeText = div.querySelector('span')?.text.trim();
          if (sizeText != null) {
            final dimensions = sizeText.toLowerCase().split('x');
            if (dimensions.length >= 2) {
              imageWidth = double.tryParse(dimensions[0].trim());
              imageHeight = double.tryParse(dimensions[1].trim());
              break;
            }
          }
        }
      }
    } else {
      final resolutionMatch = RegExp(
        r'<b>\s*Resolution:\s*</b>\s*([0-9]+)\s*x\s*([0-9]+)<br\s*/?>',
        caseSensitive: false,
      ).firstMatch(infoSection.innerHtml);
      if (resolutionMatch != null) {
        imageWidth = double.tryParse(resolutionMatch.group(1)!.trim());
        imageHeight = double.tryParse(resolutionMatch.group(2)!.trim());
      }
    }
  }

  final bodyElement = document.querySelector('body');
  final tagBlocklistNonce =
      bodyElement?.attributes['data-tag-blocklist-nonce']?.trim();
  final tagBlocklistRaw = bodyElement?.attributes['data-tag-blocklist'] ?? '';
  final blockedTags = tagBlocklistRaw
      .trim()
      .split(RegExp(r'\s+'))
      .where((tag) => tag.trim().isNotEmpty)
      .map((tag) => tag.trim().toLowerCase())
      .toSet();

  final keywordSection = document
          .querySelector('section.tags-row:not(.tags-row--meta)') ??
      document
          .querySelector('section.tags-mobile:not(.tags-mobile--meta)') ??
      document.querySelector('.submission-tags') ??
      logQuery(document, 'section.tags-row:not(.tags-row--meta)') ??
      logQuery(document, 'section.tags-mobile:not(.tags-mobile--meta)') ??
      logQuery(document, '.submission-tags') ??
      logQuery(document, '#keywords');
  final metaKeywordSection =
      document.querySelector('section.tags-row.tags-row--meta') ??
          document.querySelector('section.tags-mobile.tags-mobile--meta');
  final keywordTags = _parseTagsFromSection(
    keywordSection,
    isMeta: false,
    blockedTags: blockedTags,
  );
  final metaKeywordTags = _parseTagsFromSection(
    metaKeywordSection,
    isMeta: true,
    blockedTags: blockedTags,
  );
  final keywords = <String>[
    for (final tag in keywordTags)
      if (tag.isSearchable) tag.name,
  ];

  return OpenPostSubmissionMetadata(
    category: category,
    type: type,
    species: species,
    gender: gender,
    size: size,
    fileSize: fileSize,
    keywords: keywords,
    keywordTags: keywordTags,
    metaKeywordTags: metaKeywordTags,
    tagBlocklistNonce: tagBlocklistNonce,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  );
}

List<FaPostTag> _parseTagsFromSection(
  dom.Element? section, {
  required bool isMeta,
  required Set<String> blockedTags,
}) {
  if (section == null) return const [];
  final tags = <FaPostTag>[];
  for (final tagContainer in section.querySelectorAll('span.tags')) {
    final tagBlock = tagContainer.querySelector('a.tag-block');
    final dataTagName = tagBlock?.attributes['data-tag-name']?.trim();
    final isBlockedFromClass =
        tagBlock?.classes.contains('remove-tag') ?? false;
    final searchAnchor =
        tagContainer.querySelector('a[href^="/search/@keywords"]');
    final label = searchAnchor?.text.trim();
    final isSearchable = searchAnchor != null;

    String? fallbackLabel;
    if (!isSearchable) {
      fallbackLabel =
          tagContainer.querySelector('span.tag-invalid')?.text.trim() ??
              tagContainer.querySelector('a')?.text.trim();
    }
    final name = (dataTagName ?? label ?? fallbackLabel ?? '').trim();
    if (name.isEmpty) continue;
    if (tags.any((tag) => tag.name == name)) continue;
    final normalizedName = name.toLowerCase();
    final isBlocked =
        isBlockedFromClass || blockedTags.contains(normalizedName);
    tags.add(
      FaPostTag(
        name: name,
        isBlocked: isBlocked,
        isMeta: isMeta,
        isSearchable: isSearchable,
      ),
    );
  }
  return tags;
}
