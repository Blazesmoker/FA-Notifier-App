import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/shared/fa/fa_thumbnail_parser.dart';

Future<List<Map<String, dynamic>>> parseFaThumbnailHtml(String html) {
  return compute(_parseFaThumbnailHtml, html);
}

List<Map<String, dynamic>> _parseFaThumbnailHtml(String html) {
  final document = html_parser.parse(html);
  final figures = FaThumbnailParser.selectThumbnailFigures(document);
  final imageMetadata = <Map<String, dynamic>>[];

  for (final fig in figures) {
    final data = FaThumbnailParser.extract(fig);
    if (data == null) continue;
    imageMetadata.add({
      'url': data['thumbnailUrl'],
      'width': data['width'],
      'height': data['height'],
      'uniqueNumber': data['uniqueNumber'],
      'rating': data['rating'],
      'title': data['title'],
      'author': data['author'],
      'postUrl': data['postUrl'],
    });
  }

  return imageMetadata;
}

Future<Map<String, dynamic>> processFaImageRows({
  required List<Map<String, dynamic>> newImages,
  required List<Map<String, dynamic>> normalImagesQueue,
}) {
  return compute(
    _processFaImageRows,
    {
      'newImages': newImages,
      'normalImagesQueue': normalImagesQueue,
    },
  );
}

Map<String, dynamic> _processFaImageRows(Map<String, dynamic> payload) {
  final newImages =
      List<Map<String, dynamic>>.from(payload['newImages'] as List);
  final queue =
      List<Map<String, dynamic>>.from(payload['normalImagesQueue'] as List);
  final rows = <List<Map<String, dynamic>>>[];

  for (final image in newImages) {
    if (_isWideImage(image)) {
      if (queue.isNotEmpty) {
        rows.add([queue.removeAt(0), image]);
      } else {
        rows.add([image]);
      }
    } else {
      queue.add(image);
    }
  }

  while (queue.length >= 2) {
    rows.add([queue.removeAt(0), queue.removeAt(0)]);
  }

  if (queue.isNotEmpty) {
    rows.add([queue.removeAt(0)]);
  }

  return {
    'rows': rows,
    'queue': queue,
  };
}

bool _isWideImage(Map<String, dynamic> image) {
  final width = image['width'] as double;
  final height = image['height'] as double;
  return width / height > 1.5;
}
