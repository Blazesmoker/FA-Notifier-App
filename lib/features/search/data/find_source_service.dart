import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:fanotifier/features/search/domain/find_source_models.dart';
import 'package:fanotifier/core/network/fa_http.dart';

class FindSourceService {
  static const String _iqdbEndpoint = 'https://e621.net/iqdb_queries.json';
  static const String _fluffleEndpoint =
      'https://api.fluffle.xyz/exact-search-by-file';

  static const Set<String> _allowedDomains = {
    'furaffinity.net',
    'www.furaffinity.net',
    'e621.net',
    'www.e621.net',
  };

  Future<FindSourceSearchResult> searchSources(File file) async {
    final results = await Future.wait([
      _searchE621(file),
      _searchFluffle(file),
    ]);

    final e621Data = results[0];
    final fluffleData = results[1];

    final rawSources = <String>{};
    final postIds = <int>{};
    double? bestScore;

    void collectE621(dynamic node) {
      if (node is Map) {
        if (node['score'] != null && bestScore == null) {
          bestScore = double.tryParse(node['score'].toString());
        }

        final source = node['source'] ?? node['post']?['posts']?['source'];
        if (source is String) {
          for (final line in source.split('\n')) {
            final link = line.trim();
            if (link.isNotEmpty) {
              final normalized = _normalizeUrl(link);
              rawSources.add(normalized);
              debugPrint('[e621 IQDB] Found source: $normalized');
            }
          }
        }

        final postId = node['post']?['posts']?['id'];
        if (postId != null) {
          try {
            postIds.add(int.parse(postId.toString()));
            debugPrint('[e621 IQDB] Found post ID: $postId');
          } catch (_) {}
        }

        node.values.forEach(collectE621);
      } else if (node is List) {
        for (final childNode in node) {
          collectE621(childNode);
        }
      }
    }

    void collectFluffle(dynamic data) {
      if (data is Map) {
        final results = data['results'];
        if (results is List) {
          for (final result in results) {
            if (result is Map) {
              final match = result['match'];
              if (match != 'exact') {
                debugPrint('[Fluffle] Skipping non-exact match: $match');
                continue;
              }

              if (result['distance'] != null && bestScore == null) {
                final distance = double.tryParse(result['distance'].toString());
                if (distance != null) {
                  bestScore = distance * 100;
                }
              }

              final platform = result['platform'];
              final url = result['url'];

              if (url is String && url.isNotEmpty) {
                final normalized = _normalizeUrl(url);
                rawSources.add(normalized);
                debugPrint('[Fluffle] Found URL from $platform: $normalized');
              }

              if (platform == 'furAffinity') {
                final authors = result['authors'];
                if (authors is List) {
                  for (final author in authors) {
                    if (author is Map) {
                      final authorId = author['id'];
                      if (authorId is String && authorId.isNotEmpty) {
                        final authorUrl =
                            'https://www.furaffinity.net/user/$authorId';
                        rawSources.add(authorUrl);
                        debugPrint('[Fluffle] Found FA author: $authorUrl');
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    collectE621(e621Data);
    collectFluffle(fluffleData);

    debugPrint('=== API COLLECTION SUMMARY ===');
    debugPrint('Total raw sources collected: ${rawSources.length}');
    debugPrint('Total e621 post IDs: ${postIds.length}');

    final hasDisallowedSource = rawSources.any((sourceUrl) {
      final uri = Uri.tryParse(sourceUrl);
      if (uri == null) return true;
      final host = uri.host.toLowerCase();
      if (host.contains('e621.net')) return false;
      return !_allowedDomains.contains(host);
    });

    final faAuthor = <String>{};
    final faPosts = <String>{};
    final e621Posts = <String>{};

    for (final sourceUrl in rawSources) {
      if (!_isAllowed(sourceUrl)) continue;
      if (sourceUrl.contains('furaffinity.net')) {
        if (sourceUrl.contains('/user/') || sourceUrl.contains('/profile/')) {
          faAuthor.add(sourceUrl);
          debugPrint('FA Author link added: $sourceUrl');
        } else {
          faPosts.add(sourceUrl);
          debugPrint('FA Post link added: $sourceUrl');
        }
      }
    }

    if (!hasDisallowedSource) {
      for (final id in postIds) {
        final link = 'https://e621.net/posts/$id';
        e621Posts.add(link);
        debugPrint('e621 Post link added: $link');
      }
    } else {
      debugPrint('Disallowed source detected — suppressing e621 post links.');
    }

    final faAuthorLinks = faAuthor.toList()..sort();
    final faPostLinks = faPosts.toList()..sort();
    final e621PostLinks = e621Posts.toList()..sort();
    final combined = <String>[
      ...faAuthorLinks,
      ...faPostLinks,
      ...e621PostLinks,
    ];

    debugPrint('Total FA Author links: ${faAuthor.length}');
    debugPrint('Total FA Post links: ${faPosts.length}');
    debugPrint('Total e621 Post links: ${e621Posts.length}');
    debugPrint('=== DISPLAY BREAKDOWN ===');
    debugPrint('Final combined results: ${combined.length} links');

    return FindSourceSearchResult(
      faAuthorLinks: faAuthorLinks,
      faPostLinks: faPostLinks,
      e621PostLinks: e621PostLinks,
      combinedResults: combined,
      accuracy: bestScore,
    );
  }

  Future<dynamic> _searchE621(File file) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_iqdbEndpoint));
      request.headers['User-Agent'] = _e621UserAgent();
      request.headers['Accept'] = 'application/json';
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final response =
          await request.send().timeout(const Duration(seconds: 30));
      final body = await response.stream.bytesToString();

      debugPrint('e621 IQDB response (${response.statusCode}):');
      debugPrint(body);

      if (response.statusCode != 200) {
        throw FindSourceError('e621 IQDB failed (${response.statusCode})');
      }

      final decoded = json.decode(body);
      if (decoded is List) {
        return {'results': decoded};
      }
      return decoded;
    } catch (e) {
      debugPrint('e621 IQDB error: $e');
      return {};
    }
  }

  Future<dynamic> _searchFluffle(File file) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_fluffleEndpoint));
      request.headers['User-Agent'] = _fluffleUserAgent();
      request.fields['limit'] = '8';
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final response =
          await request.send().timeout(const Duration(seconds: 30));
      final body = await response.stream.bytesToString();

      debugPrint('Fluffle API response (${response.statusCode}):');
      debugPrint(body);

      if (response.statusCode != 200) {
        debugPrint('Fluffle API failed with status ${response.statusCode}');
        return {};
      }

      return json.decode(body);
    } catch (e) {
      debugPrint('Fluffle API error: $e');
      return {};
    }
  }

  bool _isAllowed(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return _allowedDomains.contains(uri.host.toLowerCase());
  }

  String _normalizeUrl(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String _e621UserAgent() {
    return '${FAHttp.appName}/${FAHttp.appVersion} (by Blazesmoker on e621)';
  }

  String _fluffleUserAgent() {
    return '${FAHttp.appName}/${FAHttp.appVersion} (by Blazesmoker on GitHub)';
  }
}
