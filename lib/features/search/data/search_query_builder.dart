import 'package:fanotifier/shared/fa/domain/fa_page_settings.dart';

Uri buildFaSearchUri({
  required int pageNumber,
  required Map<String, String> selectedFilters,
  required String searchQuery,
}) {
  final baseQuery = searchQuery.trim();

  final genderQuery = _buildGenderQuery(
    selectedFilters,
    useOr: (selectedFilters['mode'] ?? 'extended') == 'any',
  );

  final needsExtended = genderQuery.contains('|') || genderQuery.contains('"');
  final combinedQuery = [baseQuery, genderQuery].where((s) => s.isNotEmpty).join(' ').trim();

  final queryParams = {
    'page': pageNumber.toString(),
    'q': combinedQuery,
    'order-by': selectedFilters['order-by'] ?? 'relevancy',
    'order-direction': selectedFilters['order-direction'] ?? 'desc',
    'range': selectedFilters['range'] ?? '5years',
    'mode': needsExtended ? 'extended' : (selectedFilters['mode'] ?? 'extended'),
    'rating-general': selectedFilters['rating-general'] ?? '1',
    'rating-mature': selectedFilters['rating-mature'] ?? '1',
    'rating-adult': selectedFilters['rating-adult'] ?? '1',
    'type-art': selectedFilters['type-art'] ?? '1',
    'type-music': selectedFilters['type-music'] ?? '1',
    'type-flash': selectedFilters['type-flash'] ?? '1',
    'type-story': selectedFilters['type-story'] ?? '1',
    'type-photo': selectedFilters['type-photo'] ?? '1',
    'type-poetry': selectedFilters['type-poetry'] ?? '1',
    'perpage': FaPageSettings.resultsPerPage(selectedFilters),
  };

  for (final entry in selectedFilters.entries) {
    if (RegExp(r'^(?:type|rating)-[a-z][a-z0-9_-]*$').hasMatch(entry.key)) {
      queryParams[entry.key] = entry.value;
    }
  }

  if (selectedFilters['range'] == 'manual') {
    queryParams['range_from'] = selectedFilters['range_from'] ?? '';
    queryParams['range_to'] = selectedFilters['range_to'] ?? '';
  }

  return Uri.https('www.furaffinity.net', '/search/', queryParams);
}

String _buildGenderQuery(Map<String, String> filters, {required bool useOr}) {
  final selected = <String>[];
  for (final entry in filters.entries) {
    if (entry.value != '1' ||
        !RegExp(r'^gender-[a-z][a-z0-9_]*$').hasMatch(entry.key)) {
      continue;
    }
    final term = entry.key.substring('gender-'.length).replaceAll('_', ' ');
    selected.add(term.contains(' ') ? '"$term"' : term);
  }
  if (selected.isEmpty) return '';

  final separator = useOr ? ' | ' : ' ';
  return selected.join(separator);
}
