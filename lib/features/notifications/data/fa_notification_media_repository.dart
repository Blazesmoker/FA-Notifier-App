import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/notifications/data/fa_notification_cookie_header_provider.dart';
import 'package:fanotifier/features/notifications/data/fa_notification_media_parser.dart';
import 'package:fanotifier/features/notifications/data/simple_semaphore.dart';
import 'package:fanotifier/core/network/fa_http.dart';
import 'package:fanotifier/core/fa/fa_media_auth.dart';
import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';

class FaNotificationMediaRepository {
  FaNotificationMediaRepository({
    required this._semaphore,
    this._cookieHeaderProvider = const FaNotificationCookieHeaderProvider(),
  });

  final SimpleSemaphore _semaphore;
  final FaNotificationCookieHeaderProvider _cookieHeaderProvider;
  final Map<String, String> _avatarCache = {};
  final Map<String, String> _previewCache = {};
  final Map<String, Future<String?>> _previewInFlight = {};
  String? _previewContext;

  void refreshSubmissionPreviews() {
    _previewCache.removeWhere((_, url) => url.startsWith('assets/'));
  }

  Future<String?> fetchAvatarUrl(String username) async {
    if (username.isEmpty) return null;
    final String canonicalUsername;
    if (username.startsWith('/user/')) {
      canonicalUsername =
          username.replaceFirst('/user/', '').replaceAll('/', '');
    } else {
      canonicalUsername = username.toLowerCase().replaceAll('_', '');
    }
    final fullUrl = 'https://www.furaffinity.net/user/$canonicalUsername/';
    debugPrint('[fetchAvatarUrl] Checking $fullUrl');
    if (_avatarCache.containsKey(canonicalUsername)) {
      debugPrint(
        '[fetchAvatarUrl] Cache hit for $canonicalUsername -> ${_avatarCache[canonicalUsername]}',
      );
      return _avatarCache[canonicalUsername];
    }
    await _semaphore.acquire();
    try {
      final cookieHeader = await _cookieHeaderProvider.load();
      final response = await FAHttp.get(
        Uri.parse(fullUrl),
        headers: {
          'Cookie': ?cookieHeader,
        },
      );
      debugPrint('[fetchAvatarUrl] code=${response.statusCode}');
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        final src = parseNotificationAvatarUrl(document);
        if (src != null) {
          _avatarCache[canonicalUsername] = src;
          debugPrint('[fetchAvatarUrl] Found -> $src');
          return src;
        }
      }
    } catch (error) {
      debugPrint('[fetchAvatarUrl] Error: $error');
    } finally {
      _semaphore.release();
    }
    return null;
  }

  Future<String?> fetchSubmissionPreview(String submissionId) async {
    if (submissionId.isEmpty) return null;
    final sessionRevision = FaMediaAuth.changes.value;
    final sfwEnabled = await const SfwModePreference().loadSfwEnabled();
    final context = '$sessionRevision:$sfwEnabled';
    if (_previewContext != context) {
      _previewCache.clear();
      _previewContext = context;
    }
    final requestKey = '$context:$submissionId';
    if (_previewCache.containsKey(submissionId)) {
      debugPrint(
        '[fetchSubmissionPreview] Cache hit for submission $submissionId: ${_previewCache[submissionId]}',
      );
      return _previewCache[submissionId];
    }
    final inFlight = _previewInFlight[requestKey];
    if (inFlight != null) return inFlight;

    Future<String?> doFetch() async {
      await _semaphore.acquire();
      try {
        if (_previewContext != context ||
            sessionRevision != FaMediaAuth.changes.value) {
          return null;
        }
        final cached = _previewCache[submissionId];
        if (cached != null) return cached;
        final cookieHeader = await _cookieHeaderProvider.load();
        final url = 'https://www.furaffinity.net/view/$submissionId/';
        final response = await FAHttp.get(
          Uri.parse(url),
          headers: {
            'Cookie': ?cookieHeader,
          },
          isCancelled: () =>
              _previewContext != context ||
              sessionRevision != FaMediaAuth.changes.value,
        );
        if (_previewContext != context ||
            sessionRevision != FaMediaAuth.changes.value) {
          return null;
        }
        debugPrint(
          '[fetchSubmissionPreview] Response code for $submissionId: ${response.statusCode}',
        );
        if (response.statusCode == 200) {
          final document = html_parser.parse(response.body);
          final parsedPreview = parseNotificationSubmissionPreview(document);
          if (parsedPreview != null &&
              _previewContext == context &&
              sessionRevision == FaMediaAuth.changes.value) {
            _previewCache[submissionId] = parsedPreview.url;
          }
          return parsedPreview?.url;
        }
      } catch (error) {
        debugPrint(
          '[fetchSubmissionPreview] Error fetching preview for submission $submissionId: $error',
        );
      } finally {
        _semaphore.release();
        _previewInFlight.remove(requestKey);
      }
      return null;
    }

    final future = doFetch();
    _previewInFlight[requestKey] = future;
    return future;
  }
}
