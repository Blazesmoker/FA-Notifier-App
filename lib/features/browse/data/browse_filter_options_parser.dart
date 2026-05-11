import 'package:html/parser.dart' as html_parser;

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
