class ContentRatingFilters {
  static const String ratingGeneralKey = 'rating-general';
  static const String ratingMatureKey = 'rating-mature';
  static const String ratingAdultKey = 'rating-adult';

  static const Map<String, String> _defaultBrowseFields = {
    'Category': '1',
    'Type': '1',
    'Species': '1',
    'Gender': '0',
  };

  static const Map<String, String> _defaultSearchFields = {
    'order-by': 'relevancy',
    'order-direction': 'desc',
    'range': '5years',
    'mode': 'extended',
    'type-art': '1',
    'type-music': '1',
    'type-flash': '1',
    'type-story': '1',
    'type-photo': '1',
    'type-poetry': '1',
    'gender-male': '0',
    'gender-female': '0',
    'gender-trans_male': '0',
    'gender-trans_female': '0',
    'gender-intersex': '0',
    'gender-non_binary': '0',
    'range_from': '',
    'range_to': '',
  };

  static Map<String, String> defaultRatingFilters({required bool sfwEnabled}) {
    return {
      ratingGeneralKey: '1',
      ratingMatureKey: sfwEnabled ? '0' : '1',
      ratingAdultKey: sfwEnabled ? '0' : '1',
    };
  }

  static Map<String, String> defaultBrowseFilters({required bool sfwEnabled}) {
    return {
      ..._defaultBrowseFields,
      ...defaultRatingFilters(sfwEnabled: sfwEnabled),
    };
  }

  static Map<String, String> defaultSearchFilters({required bool sfwEnabled}) {
    return {
      ..._defaultSearchFields,
      ...defaultRatingFilters(sfwEnabled: sfwEnabled),
    };
  }

  static Map<String, String> normalizeBrowseFilters(
    Map<String, String> filters, {
    required bool sfwEnabled,
  }) {
    final normalized = defaultBrowseFilters(sfwEnabled: sfwEnabled);
    normalized['Category'] =
        filters['Category'] ?? filters['cat'] ?? normalized['Category']!;
    normalized['Type'] =
        filters['Type'] ?? filters['atype'] ?? normalized['Type']!;
    normalized['Species'] =
        filters['Species'] ?? filters['species'] ?? normalized['Species']!;
    normalized['Gender'] =
        filters['Gender'] ?? filters['gender'] ?? normalized['Gender']!;
    normalized[ratingGeneralKey] =
        filters[ratingGeneralKey] ?? normalized[ratingGeneralKey]!;
    normalized[ratingMatureKey] =
        filters[ratingMatureKey] ?? normalized[ratingMatureKey]!;
    normalized[ratingAdultKey] =
        filters[ratingAdultKey] ?? normalized[ratingAdultKey]!;
    return normalized;
  }

  static Map<String, String> normalizeSearchFilters(
    Map<String, String> filters, {
    required bool sfwEnabled,
  }) {
    return {
      ...defaultSearchFilters(sfwEnabled: sfwEnabled),
      ...filters,
    };
  }

  static bool allowsExplicitNsfw(Map<String, String> filters) {
    return filters[ratingMatureKey] == '1' || filters[ratingAdultKey] == '1';
  }

  static String effectiveSfwCookieValue({
    required bool globalSfwEnabled,
    required Map<String, String> filters,
  }) {
    final effectiveSfwEnabled =
        globalSfwEnabled && !allowsExplicitNsfw(filters);
    return effectiveSfwEnabled ? '1' : '0';
  }
}
