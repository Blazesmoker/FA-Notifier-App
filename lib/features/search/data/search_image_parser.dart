import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/core/logging/app_logging.dart';
import 'package:fanotifier/features/search/data/search_filter_options_parser.dart';
import 'package:fanotifier/features/search/domain/search_page_data.dart';
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';
import 'package:fanotifier/shared/fa/fa_thumbnail_processing.dart';

Future<SearchPageData> parseSearchImageHtml(String html) async {
  final parsed = await parseSearchPageHtml(html, recovered: true);
  return parsed.page;
}

Future<SearchPageParseResult> parseSearchPageHtml(
  String html, {
  bool recovered = false,
  bool filtersOnly = false,
}) async {
  final result = await compute(
    _parseSearchPage,
    (html: html, recovered: recovered, filtersOnly: filtersOnly),
    debugLabel: 'search_page_parse',
  );
  if (!filtersOnly) {
    kDebugPrint(
      '[Search] HTML parser found ${result.images.length} usable thumbnails.',
    );
  }
  return result;
}

SearchPageParseResult _parseSearchPage(
  ({String html, bool recovered, bool filtersOnly}) input,
) {
  final document = html_parser.parse(input.html);
  final message = input.recovered
      ? null
      : parseFaSystemMessage(input.html, parsedDocument: document);
  return SearchPageParseResult(
    images: message == null && !input.filtersOnly
        ? parseFaThumbnailDocument(document)
        : [],
    filterOptions: message == null ||
            (input.filtersOnly && !message.isMaintenanceOrUnavailable)
        ? parseSearchFilterDocument(document)
        : null,
    systemMessage: message,
  );
}

class SearchPageParseResult {
  const SearchPageParseResult({
    required this.images,
    required this.systemMessage,
    this.filterOptions,
  });

  final List<Map<String, dynamic>> images;
  final FaSystemMessage? systemMessage;
  final FaFilterOptions? filterOptions;

  SearchPageData get page =>
      SearchPageData(images: images, filterOptions: filterOptions);
}
