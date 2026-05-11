import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/submissions/data/submission_favorite_links_parser.dart';
import 'package:FANotifier/features/submissions/domain/submission_fetch_models.dart';

SubmissionData parseSubmissionDetailData(List<int> bodyBytes) {
  final doc = html_parser.parse(utf8.decode(bodyBytes));
  final isClassic =
      doc.body?.attributes['data-static-path']?.contains('/themes/classic') ??
          false;

  String? hqUrl;
  if (isClassic) {
    final img = doc.querySelector('img#submissionImg');
    if (img != null) {
      final fullview = img.attributes['data-fullview-src'];
      if (fullview != null && fullview.isNotEmpty) {
        hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
      } else {
        final src = img.attributes['src'] ?? '';
        if (src.isNotEmpty) {
          hqUrl = src.startsWith('//') ? 'https:$src' : src;
        }
      }
    }
  } else {
    final subArea = doc.querySelector('div.submission-area.submission-image');
    if (subArea != null) {
      final img = subArea.querySelector('img#submissionImg');
      if (img != null) {
        final fullview = img.attributes['data-fullview-src'];
        if (fullview != null && fullview.isNotEmpty) {
          hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
        } else {
          final src = img.attributes['src'] ?? '';
          if (src.isNotEmpty) {
            hqUrl = src.startsWith('//') ? 'https:$src' : src;
          }
        }
      }
    }
  }
  hqUrl ??= '';

  final favoriteLinks = parseSubmissionFavoriteLinksFromDocument(
    doc,
    includeClassicFallback: isClassic,
  );

  return SubmissionData(
    hqUrl: hqUrl,
    isFav: favoriteLinks.isFavorited,
    favUrl: favoriteLinks.favUrl,
    unfavUrl: favoriteLinks.unfavUrl,
  );
}
