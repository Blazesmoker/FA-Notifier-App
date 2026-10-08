import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';

class SearchPageData {
  const SearchPageData({required this.images, this.filterOptions});

  final List<Map<String, dynamic>> images;
  final FaFilterOptions? filterOptions;
}
