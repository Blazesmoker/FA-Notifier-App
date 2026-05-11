import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:FANotifier/features/browse/data/browse_filter_options_parser.dart';
import 'package:FANotifier/shared/fa/fa_http.dart';

Future<Map<String, List<Map<String, String>>>> fetchBrowseFilterOptions() async {
  try {
    debugPrint('Fetching all filters...');
    final response = await http.get(
      Uri.parse('https://www.furaffinity.net/browse/'),
      headers: {'User-Agent': FAHttp.userAgent},
    );

    if (response.statusCode == 200) {
      final loadedFilterOptions = parseBrowseFilterOptions(response.body);
      for (final entry in loadedFilterOptions.entries) {
        if (entry.value.isNotEmpty) {
          debugPrint('${entry.key}: ${entry.value.length} options fetched.');
        } else {
          debugPrint('Select element for "${entry.key}" not found.');
        }
      }
      return loadedFilterOptions;
    }

    debugPrint('Failed to fetch filters. Status code: ${response.statusCode}');
    return emptyBrowseFilterOptions();
  } catch (e) {
    debugPrint('Error fetching filter data: $e');
    return emptyBrowseFilterOptions();
  }
}

Map<String, List<Map<String, String>>> emptyBrowseFilterOptions() => {
      'cat': [],
      'atype': [],
      'species': [],
      'gender': [],
    };
