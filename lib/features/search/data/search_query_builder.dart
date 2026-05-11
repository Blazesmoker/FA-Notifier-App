Uri buildFaSearchUri({
  required int pageNumber,
  required Map<String, String> selectedFilters,
  required String searchQuery,
}) {
  final baseQ = searchQuery.trim();

  final genderQ = _buildGenderQuery(
    selectedFilters,
    useOr: (selectedFilters['mode'] ?? 'extended') == 'any',
  );

  final needsExtended = genderQ.contains('|') || genderQ.contains('"');
  final q = [baseQ, genderQ].where((s) => s.isNotEmpty).join(' ').trim();

  final queryParams = {
    'page': pageNumber.toString(),
    'q': q,
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
    'perpage': selectedFilters['perpage'] ?? '72',
  };

  if (selectedFilters['range'] == 'manual') {
    queryParams['range_from'] = selectedFilters['range_from'] ?? '';
    queryParams['range_to'] = selectedFilters['range_to'] ?? '';
  }

  return Uri.https('www.furaffinity.net', '/search/', queryParams);
}

String _buildGenderQuery(Map<String, String> filters, {required bool useOr}) {
  const map = {
    'male': 'male',
    'female': 'female',
    'trans_male': '"trans male"',
    'trans_female': '"trans female"',
    'intersex': 'intersex',
    'non_binary': '"non binary"',
  };

  final selected = <String>[];
  map.forEach((key, term) {
    if (filters['gender-$key'] == '1') selected.add(term);
  });
  if (selected.isEmpty) return '';

  final glue = useOr ? ' | ' : ' ';
  return selected.join(glue);
}
