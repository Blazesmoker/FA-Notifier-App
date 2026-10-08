import 'package:fanotifier/features/ads/domain/fa_ad_models.dart';
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';

class BrowsePageData {
  const BrowsePageData({
    required this.images,
    required this.ads,
    this.filterOptions,
    this.modeMatchesRequest = true,
  });

  final List<Map<String, dynamic>> images;
  final FaAdPageMetadata? ads;
  final FaFilterOptions? filterOptions;
  final bool modeMatchesRequest;
}

class BrowseGridSection {
  const BrowseGridSection({
    required this.pageNumber,
    required this.rows,
    required this.ads,
  });

  final int pageNumber;
  final List<List<Map<String, dynamic>>> rows;
  final FaAdPageMetadata? ads;
}
