import 'package:html/dom.dart' as dom;

/// Shared thumbnail parsing helpers for FA "gallery" style grids.
///
/// Extracts, from a single `<figure>`:
/// - rating: "general" | "mature" | "adult" | null
/// - title: submission title (from `<figcaption>`)
/// - author: display name (from `<figcaption>`) with fallback to username class
/// - authorProfileUrl: author profile link from href (normalized to path/full url)
/// - postUrl, uniqueNumber, thumbnailUrl, width, height
///
/// This is intentionally shared across screens to avoid per-screen parsers.
class FaThumbnailParser {
  FaThumbnailParser._();

  static const String _thumbSelector =
      'img[src^="//t.furaffinity.net/"], img[src^="https://t.furaffinity.net/"], img[src^="http://t.furaffinity.net/"]';

  /// Returns only figures that look like FA submission thumbnails.
  static List<dom.Element> selectThumbnailFigures(dom.Document doc) {
    final figures = doc.querySelectorAll('figure');
    return figures.where((fig) {
      final hasThumb = fig.querySelector(_thumbSelector) != null;
      final hasViewLink = fig.querySelector('a[href*="/view/"]') != null;
      return hasThumb && hasViewLink;
    }).toList(growable: false);
  }

  static String? extractRating(dom.Element figure) {
    final classes = figure.classes;
    if (classes.contains('r-general')) return 'general';
    if (classes.contains('r-mature')) return 'mature';
    if (classes.contains('r-adult')) return 'adult';
    return null;
  }

  static String? extractTitle(dom.Element figure) {
    final titleLink = figure.querySelector('figcaption p a[href*="/view/"]') ??
        figure.querySelector('figcaption p a') ??
        figure.querySelector('figcaption a');
    final title = titleLink?.text.trim();
    return (title != null && title.isNotEmpty) ? title : null;
  }

  static String? extractAuthor(dom.Element figure) {
    final authorLink = figure.querySelector('figcaption a[href^="/user/"]') ??
        figure.querySelector('figcaption p a[href^="/user/"]') ??
        figure.querySelector('a[href^="/user/"]');
    final name = authorLink?.text.trim();
    if (name != null && name.isNotEmpty) return name;

    // Fallback: figure class often includes `u-username`
    try {
      final usernameClass = figure.classes.firstWhere((c) => c.startsWith('u-'));
      final fallback = usernameClass.substring(2).trim();
      return fallback.isNotEmpty ? fallback : null;
    } catch (_) {
      return null;
    }
  }

  static String? extractAuthorProfileUrl(dom.Element figure) {
    final authorLink = figure.querySelector('figcaption a[href^="/user/"]') ??
        figure.querySelector('figcaption p a[href^="/user/"]') ??
        figure.querySelector('a[href^="/user/"]');
    final href = authorLink?.attributes['href']?.trim();
    if (href == null || href.isEmpty) return null;
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    if (href.startsWith('/')) return href;
    return '/$href';
  }

  static String? extractPostUrl(dom.Element figure) {
    final submissionLink = figure.querySelector('a[href*="/view/"]');
    final href = submissionLink?.attributes['href']?.trim();
    return (href != null && href.isNotEmpty) ? href : null;
  }

  static String extractSubmissionId(String postUrlOrHref) {
    final match = RegExp(r'/view/(\d+)/').firstMatch(postUrlOrHref);
    return match?.group(1) ?? '';
  }

  static String? extractThumbnailUrl(dom.Element figure) {
    final thumbnailImage = figure.querySelector(_thumbSelector);
    final src = thumbnailImage?.attributes['src']?.trim();
    if (src == null || src.isEmpty) return null;
    if (src.startsWith('//')) return 'https:$src';
    return src;
  }

  static double? extractDataWidth(dom.Element figure) {
    final thumbnailImage = figure.querySelector(_thumbSelector);
    final width = thumbnailImage?.attributes['data-width'];
    return width == null ? null : double.tryParse(width);
  }

  static double? extractDataHeight(dom.Element figure) {
    final thumbnailImage = figure.querySelector(_thumbSelector);
    final height = thumbnailImage?.attributes['data-height'];
    return height == null ? null : double.tryParse(height);
  }

  /// Extract a normalized map for use by the various grids.
  ///
  /// Keys:
  /// - postUrl (String)
  /// - uniqueNumber (String)
  /// - thumbnailUrl (String)
  /// - width (double)
  /// - height (double)
  /// - rating (String? "general"|"mature"|"adult")
  /// - title (String?)
  /// - author (String?)
  /// - authorProfileUrl (String?)
  static Map<String, dynamic>? extract(dom.Element figure) {
    final postUrl = extractPostUrl(figure);
    final thumbnailUrl = extractThumbnailUrl(figure);
    final width = extractDataWidth(figure);
    final height = extractDataHeight(figure);
    if (postUrl == null || thumbnailUrl == null || width == null || height == null) return null;

    final submissionId = extractSubmissionId(postUrl);
    if (submissionId.isEmpty) return null;

    return {
      'postUrl': postUrl,
      'uniqueNumber': submissionId,
      'thumbnailUrl': thumbnailUrl,
      'width': width,
      'height': height,
      'rating': extractRating(figure),
      'title': extractTitle(figure),
      'author': extractAuthor(figure),
      'authorProfileUrl': extractAuthorProfileUrl(figure),
    };
  }
}


