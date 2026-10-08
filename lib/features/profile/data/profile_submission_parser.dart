import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/profile/domain/profile_submission_data.dart';
import 'package:fanotifier/shared/fa/parsing/submission_favorite_links_parser.dart';

Future<ProfileSubmissionData> parseProfileSubmissionPage(List<int> bodyBytes) {
  return compute(
    _parseProfileSubmissionPage,
    bodyBytes,
    debugLabel: 'profile_submission_detail_parse',
  );
}

ProfileSubmissionData _parseProfileSubmissionPage(List<int> bodyBytes) {
  final doc = html_parser.parse(utf8.decode(bodyBytes));
  String hqUrl = '';
  final subArea = doc.querySelector('div.submission-area.submission-image');
  if (subArea != null) {
    final img = subArea.querySelector('img#submissionImg');
    if (img != null) {
      final fullview = img.attributes['data-fullview-src'];
      if (fullview != null && fullview.isNotEmpty) {
        hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
      } else {
        final src = img.attributes['src'];
        if (src != null && src.isNotEmpty) {
          hqUrl = src.startsWith('//') ? 'https:$src' : src;
        }
      }
    }
  }

  if (hqUrl.isEmpty) {
    final img = doc.querySelector('img#submissionImg');
    if (img != null) {
      final fullview = img.attributes['data-fullview-src'];
      if (fullview != null && fullview.isNotEmpty) {
        hqUrl = fullview.startsWith('//') ? 'https:$fullview' : fullview;
      } else {
        final src = img.attributes['src'];
        if (src != null && src.isNotEmpty) {
          hqUrl = src.startsWith('//') ? 'https:$src' : src;
        }
      }
    }
  }

  final favoriteLinks = parseSubmissionFavoriteLinksFromDocument(
    doc,
    includeClassicFallback: true,
  );
  return ProfileSubmissionData(
    hqUrl: hqUrl,
    isFav: favoriteLinks.isFavorited,
    favUrl: favoriteLinks.favUrl,
    unfavUrl: favoriteLinks.unfavUrl,
  );
}
