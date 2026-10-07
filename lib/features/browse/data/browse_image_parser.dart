import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/features/ads/data/fa_ad_parser.dart';
import 'package:fanotifier/features/browse/domain/browse_page_data.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';
import 'package:fanotifier/shared/fa/fa_thumbnail_processing.dart';

Future<BrowsePageParseResult> parseBrowsePageHtml({
  required String html,
  required Uri documentUri,
  required bool sfwEnabled,
  bool recovered = false,
}) async {
  final result = await compute(
    _parseBrowsePage,
    _BrowsePageParseInput(html, documentUri, sfwEnabled, recovered),
    debugLabel: 'browse_page_parse',
  );
  if (result.systemMessage == null) {
    kDebugPrint(
      '[Browse] HTML parser found ${result.page.images.length} usable thumbnails.',
    );
  }
  return result;
}

BrowsePageParseResult _parseBrowsePage(_BrowsePageParseInput input) {
  final document = html_parser.parse(input.html);
  final systemMessage = input.recovered
      ? null
      : parseFaSystemMessage(input.html, parsedDocument: document);
  if (systemMessage != null) {
    return BrowsePageParseResult(
      page: const BrowsePageData(images: [], ads: null),
      systemMessage: systemMessage,
    );
  }
  return BrowsePageParseResult(
    page: BrowsePageData(
      images: parseFaThumbnailDocument(document),
      modeMatchesRequest: !input.recovered ||
          faAdPageModeMatches(input.html, input.sfwEnabled),
      ads: parseFaAdPage(
        html: input.html,
        documentUri: input.documentUri,
        sfwEnabled: input.sfwEnabled,
        parsedDocument: document,
      ),
    ),
  );
}

class BrowsePageParseResult {
  const BrowsePageParseResult({required this.page, this.systemMessage});

  final BrowsePageData page;
  final FaSystemMessage? systemMessage;
}

class _BrowsePageParseInput {
  const _BrowsePageParseInput(
    this.html, this.documentUri, this.sfwEnabled, this.recovered,
  );

  final String html;
  final Uri documentUri;
  final bool sfwEnabled;
  final bool recovered;
}
