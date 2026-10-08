import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';
import 'package:fanotifier/shared/fa/domain/fa_page_settings.dart';

Map<String, List<Map<String, String>>> parseBrowseFilterOptions(String html) {
  final document = html_parser.parse(html);
  final loadedFilterOptions = <String, List<Map<String, String>>>{};
  final filterNames = ['cat', 'atype', 'species', 'gender'];

  for (final filterName in filterNames) {
    final selectElement = document.querySelector('select[name="$filterName"]');
    if (selectElement != null) {
      final options = selectElement.querySelectorAll('option').map((e) {
        final label = e.text.trim();
        final value = e.attributes['value'] ?? '';
        return {'label': label, 'value': value};
      }).toList();
      loadedFilterOptions[filterName] = options;
    } else {
      loadedFilterOptions[filterName] = [];
    }
  }

  return loadedFilterOptions;
}

FaFilterOptions? parseBrowseFilterDocument(Document document) {
  final firstSelect = document.querySelector('select[name="cat"]');
  var form = firstSelect?.parent;
  while (form != null && form.localName != 'form') {
    form = form.parent;
  }
  if (form == null) return null;
  final groups = <String, List<FaFilterOption>>{};
  for (final name in [
    'cat',
    'atype',
    'species',
    'gender',
    FaPageSettings.perPageKey,
  ]) {
    final elements = form.querySelectorAll('select[name="$name"] option');
    if (elements.isEmpty ||
        elements.any((option) =>
            !option.attributes.containsKey('value') ||
            option.text.trim().isEmpty)) {
      return null;
    }
    final options = elements
        .map((option) => FaFilterOption(
              field: name,
              value: option.attributes['value']!,
              label: option.text.trim(),
            ))
        .toList();
    if (options.isEmpty ||
        options.map((option) => option.value).toSet().length != options.length) {
      return null;
    }
    groups[name] = options;
  }
  if (groups[FaPageSettings.perPageKey]!.any(
    (option) => FaPageSettings.positiveInteger(option.value) == null,
  )) {
    return null;
  }
  return FaFilterOptions(groups);
}
