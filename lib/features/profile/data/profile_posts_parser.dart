import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/profile/domain/profile_posts_parse_result.dart';
import 'package:fanotifier/features/profile/domain/fa_folder.dart';
import 'package:fanotifier/shared/fa/fa_thumbnail_parser.dart';

class ProfileGalleryHtmlParseResult {
  final List<Map<String, dynamic>> posts;
  final String? nextPageUrl;
  final List<FaFolder> folders;

  ProfileGalleryHtmlParseResult({
    required this.posts,
    this.nextPageUrl,
    required this.folders,
  });
}

ProfileGalleryHtmlParseResult parseProfileGalleryHtml(
  String html,
  String currentUrl, {
  String? selectedFolderUrl,
}) {
  final document = html_parser.parse(html);
  final figures = FaThumbnailParser.selectThumbnailFigures(document);
  final posts = <Map<String, dynamic>>[];

  for (final fig in figures) {
    final data = FaThumbnailParser.extract(fig);
    if (data == null) continue;
    posts.add({
      'postUrl': data['postUrl'],
      'uniqueNumber': data['uniqueNumber'],
      'thumbnailUrl': data['thumbnailUrl'],
      'width': data['width'],
      'height': data['height'],
      'rating': data['rating'],
      'title': data['title'],
      'author': data['author'],
      'authorProfileUrl': data['authorProfileUrl'],
      'initialIsFav': null,
    });
  }

  return ProfileGalleryHtmlParseResult(
    posts: posts,
    nextPageUrl: _findNextPageUrl(document, currentUrl),
    folders: _parseGalleryFolders(document, selectedFolderUrl: selectedFolderUrl),
  );
}

ProfilePostsParseResult parseProfileFavoritePostsHtml(
  String html,
  String currentUrl,
) {
  return _parseProfileGridPostsHtml(html, currentUrl);
}

ProfilePostsParseResult parseProfileScrapsPostsHtml(
  String html,
  String currentUrl,
) {
  return _parseProfileGridPostsHtml(html, currentUrl);
}

ProfilePostsParseResult _parseProfileGridPostsHtml(
  String html,
  String currentUrl,
) {
  final document = html_parser.parse(html);
  final figures = FaThumbnailParser.selectThumbnailFigures(document);
  final posts = <Map<String, dynamic>>[];

  for (final fig in figures) {
    final data = FaThumbnailParser.extract(fig);
    if (data == null) continue;
    posts.add({
      'url': data['thumbnailUrl'],
      'width': data['width'],
      'height': data['height'],
      'uniqueNumber': data['uniqueNumber'],
      'postUrl': data['postUrl'],
      'rating': data['rating'],
      'title': data['title'],
      'author': data['author'],
      'authorProfileUrl': data['authorProfileUrl'],
    });
  }

  return ProfilePostsParseResult(
    posts: posts,
    nextPageUrl: _findNextPageUrl(document, currentUrl),
  );
}

String? _findNextPageUrl(html_dom.Document document, String currentUrl) {
  for (var form in document.querySelectorAll('form')) {
    final button = form.querySelector('button[type="submit"]');
    if (button != null && button.text.trim().toLowerCase() == 'next') {
      final action = form.attributes['action'];
      if (action != null && action.isNotEmpty) {
        return Uri.parse(currentUrl).resolve(action).toString();
      }
    }
  }
  return null;
}

List<FaFolder> _parseGalleryFolders(
  html_dom.Document document, {
  String? selectedFolderUrl,
}) {
  final folderDiv = document.querySelector('div.folder-list');
  final folders = <FaFolder>[];
  if (folderDiv == null) return folders;

  final ulElements = folderDiv.querySelectorAll('ul');
  for (var ul in ulElements) {
    final liElements = ul.querySelectorAll('li');
    for (var li in liElements) {
      final aElem = li.querySelector('a.dotted');
      if (aElem != null) {
        final href = aElem.attributes['href'] ?? '';
        final title = aElem.text.trim();
        final fullUrl =
            'https://www.furaffinity.net$href'.replaceAll(RegExp(r'/$'), '');
        folders.add(FaFolder(name: title, url: fullUrl));
      } else {
        final strongElem = li.querySelector('strong');
        if (strongElem != null) {
          final title = strongElem.text.trim();
          final url = (selectedFolderUrl ?? '').replaceAll(RegExp(r'/$'), '');
          folders.add(FaFolder(name: title, url: url));
        }
      }
    }
  }

  return folders;
}
