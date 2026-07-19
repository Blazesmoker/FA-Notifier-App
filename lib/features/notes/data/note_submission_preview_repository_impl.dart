import 'dart:async';

import 'package:FANotifier/core/fa/fa_media_auth.dart';
import 'package:FANotifier/core/network/fa_http.dart';
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/notes/data/note_submission_preview_parser.dart';
import 'package:FANotifier/features/notes/domain/note_google_image_resolver.dart';
import 'package:FANotifier/features/notes/domain/note_image_preview_link.dart';
import 'package:FANotifier/features/notes/domain/note_submission_preview.dart';
import 'package:FANotifier/features/notes/domain/note_submission_preview_repository.dart';
import 'package:FANotifier/features/submissions/domain/openpost_repository.dart';
import 'package:flutter/foundation.dart';

class NoteSubmissionPreviewRepositoryImpl
    implements NoteSubmissionPreviewRepository {
  NoteSubmissionPreviewRepositoryImpl({
    required OpenPostRepository openPostRepository,
    required NoteGoogleImageResolver googleImageResolver,
    SfwModePreference sfwModePreference = const SfwModePreference(),
  })  : _openPostRepository = openPostRepository,
        _googleImageResolver = googleImageResolver,
        _sfwModePreference = sfwModePreference;

  final OpenPostRepository _openPostRepository;
  final NoteGoogleImageResolver _googleImageResolver;
  final SfwModePreference _sfwModePreference;
  final Map<String, NoteSubmissionPreview> _cache = {};
  final Map<String, Future<NoteSubmissionPreview?>> _inFlight = {};
  final Set<String> _failedGoogleCacheKeys = {};
  Future<void> _confirmationQueue = Future<void>.value();

  @override
  Future<NoteSubmissionPreview?> loadPreview(
    String submissionUrl, {
    required Future<bool> Function() confirmNsfw,
  }) async {
    final link = NoteImagePreviewLink.tryParse(submissionUrl);
    if (link == null) {
      _logPreview('unsupported link url=$submissionUrl');
      return null;
    }
    _logPreview(
      'load start source=${link.source.name} url=${link.url}',
    );
    final cacheKey = notePreviewCacheKey(link);
    final cached = _cache[cacheKey];
    if (cached != null) {
      _logPreview('cache hit source=${link.source.name} key=$cacheKey');
      return cached;
    }
    if (link.source == NoteImagePreviewSource.googleImages &&
        _failedGoogleCacheKeys.contains(cacheKey)) {
      _logPreview(
        'failure cache hit source=${link.source.name} key=$cacheKey',
      );
      return null;
    }
    final pending = _inFlight[cacheKey];
    if (pending != null) {
      _logPreview(
        'in-flight hit source=${link.source.name} key=$cacheKey',
      );
      return pending;
    }

    final future = _loadPreview(link, confirmNsfw);
    _inFlight[cacheKey] = future;
    try {
      final preview = await future;
      if (preview != null) {
        _cache[cacheKey] = preview;
        _logPreview(
          'load success source=${link.source.name} '
          'bytes=${preview.imageBytes.length} image=${preview.imageUrl}',
        );
      } else {
        if (link.source == NoteImagePreviewSource.googleImages) {
          _failedGoogleCacheKeys.add(cacheKey);
        }
        _logPreview(
          'load returned no preview source=${link.source.name} '
          'url=${link.url}',
        );
      }
      return preview;
    } catch (error, stackTrace) {
      _logPreviewError(
        'load exception source=${link.source.name} url=${link.url}',
        error,
        stackTrace,
      );
      rethrow;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<NoteSubmissionPreview?> _loadPreview(
    NoteImagePreviewLink link,
    Future<bool> Function() confirmNsfw,
  ) async {
    if (link.source != NoteImagePreviewSource.furAffinity) {
      return _loadExternalPreview(link);
    }

    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    var page = await _openPostRepository.fetchPage(
      url: link.url,
      sfwEnabled: sfwEnabled,
      nsfwAllowed: false,
    );
    if (sfwEnabled &&
        (page.matureContentWarning || page.oldMatureImageError)) {
      if (!await _confirmNsfwInOrder(confirmNsfw)) {
        _logPreview('FA NSFW confirmation declined url=${link.url}');
        return null;
      }
      page = await _openPostRepository.fetchPage(
        url: link.url,
        sfwEnabled: sfwEnabled,
        nsfwAllowed: true,
        skipSfw: true,
      );
    }
    if (page.statusCode != 200 || !page.isHtml) {
      _logPreview(
        'FA page rejected status=${page.statusCode} '
        'isHtml=${page.isHtml} bytes=${page.bodyBytes.length} '
        'url=${link.url}',
      );
      return null;
    }

    final imageUrl =
        parseNoteSubmissionHighQualityImageUrl(page.bodyBytes);
    if (imageUrl == null) {
      _logPreview(
        'FA image URL not found pageBytes=${page.bodyBytes.length} '
        'url=${link.url}',
      );
      return null;
    }
    _logPreview('FA image candidate url=$imageUrl');
    return _loadImage(
      sourceUrl: link.url,
      imageUrl: imageUrl,
      useFaMediaAuth: true,
    );
  }

  Future<NoteSubmissionPreview?> _loadExternalPreview(
    NoteImagePreviewLink link,
  ) async {
    var resolvedLink = link;
    final imageUrls = <String>[];
    final directImageUrl = directNotePreviewImageUrl(link);
    if (directImageUrl != null) {
      imageUrls.add(directImageUrl);
      _logPreview(
        'direct image candidate source=${link.source.name} '
        'image=$directImageUrl',
      );
    }

    if (link.source == NoteImagePreviewSource.googleImages) {
      final selectedId = googleImagesSelectedId(link);
      if (selectedId == null) {
        _logPreview(
          'Google selected ID not found url=${link.url}',
        );
        return null;
      }
      final imageUrl =
          await _googleImageResolver.resolveHighQualityImageUrl(
        pageUri: link.uri,
        selectedId: selectedId,
      );
      if (imageUrl != null) {
        imageUrls.add(imageUrl);
        _logPreview(
          'WebView image candidate source=${link.source.name} '
          'image=$imageUrl',
        );
      } else {
        _logPreview(
          'WebView image URL not found selectedId=$selectedId',
        );
      }
    }

    if (link.source == NoteImagePreviewSource.googleImageShare) {
      final pageUri = notePreviewPageUri(link);
      _logPreview(
        'redirect request source=${link.source.name} url=$pageUri',
      );
      final result = await FAHttp.getWithResolvedUri(
        pageUri,
        headers: {
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );
      final page = result.response;
      final contentType =
          (page.headers['content-type'] ?? '').toLowerCase();
      _logPreview(
        'redirect response source=${link.source.name} '
        'status=${page.statusCode} type=$contentType '
        'bytes=${page.bodyBytes.length} resolved=${result.resolvedUri}',
      );
      final parsedResolvedLink = NoteImagePreviewLink.tryParse(
        result.resolvedUri.toString(),
      );
      if (parsedResolvedLink != null) {
        resolvedLink = parsedResolvedLink;
        _logPreview(
          'redirect recognized source=${link.source.name} '
          'resolvedSource=${resolvedLink.source.name} '
          'resolved=${resolvedLink.url}',
        );
        final resolvedDirectImageUrl =
            directNotePreviewImageUrl(resolvedLink);
        if (resolvedDirectImageUrl != null) {
          imageUrls.add(resolvedDirectImageUrl);
          _logPreview(
            'redirect image candidate source=${link.source.name} '
            'image=$resolvedDirectImageUrl',
          );
        }
      } else {
        _logPreview(
          'redirect target unsupported source=${link.source.name} '
          'resolved=${result.resolvedUri}',
        );
      }
      if (imageUrls.isEmpty) {
        if (page.statusCode != 200 ||
            page.bodyBytes.isEmpty ||
            (!contentType.contains('text/html') &&
                !contentType.contains('application/xhtml+xml'))) {
          _logPreview(
            'redirect page rejected source=${link.source.name} '
            'status=${page.statusCode} type=$contentType '
            'bytes=${page.bodyBytes.length} '
            'resolved=${result.resolvedUri}',
          );
          return null;
        }
        imageUrls.addAll(
          parseNotePreviewPageImageUrls(
            resolvedLink,
            page.bodyBytes,
          ),
        );
        _logPreview(
          'redirect parsed candidates source=${link.source.name} '
          'count=${imageUrls.length} values=$imageUrls',
        );
      }
    }

    if (imageUrls.isEmpty &&
        link.source != NoteImagePreviewSource.googleImageShare &&
        link.source != NoteImagePreviewSource.googleImages) {
      final pageUri = notePreviewPageUri(link);
      _logPreview(
        'page request source=${link.source.name} url=$pageUri',
      );
      final page = await FAHttp.get(
        pageUri,
        headers: {
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );
      final contentType =
          (page.headers['content-type'] ?? '').toLowerCase();
      _logPreview(
        'page response source=${link.source.name} '
        'status=${page.statusCode} type=$contentType '
        'bytes=${page.bodyBytes.length} url=$pageUri',
      );
      final pageAccepted = page.statusCode == 200 &&
          page.bodyBytes.isNotEmpty &&
          (contentType.contains('text/html') ||
              contentType.contains('application/xhtml+xml'));
      if (!pageAccepted) {
        _logPreview(
          'page rejected source=${link.source.name} '
          'status=${page.statusCode} type=$contentType '
          'bytes=${page.bodyBytes.length} url=$pageUri',
        );
      } else {
        imageUrls.addAll(
          parseNotePreviewPageImageUrls(link, page.bodyBytes),
        );
        _logPreview(
          'parsed candidates source=${link.source.name} '
          'count=${imageUrls.length} values=$imageUrls',
        );
      }
      if (imageUrls.isEmpty && !pageAccepted) return null;
    }
    for (final imageUrl in imageUrls) {
      try {
        _logPreview(
          'image request source=${link.source.name} image=$imageUrl',
        );
        final preview = await _loadImage(
          sourceUrl: link.url,
          imageUrl: imageUrl,
          referer: notePreviewPageUri(resolvedLink).toString(),
          useFaMediaAuth: false,
        );
        if (preview != null) return preview;
        _logPreview(
          'image candidate returned no preview '
          'source=${link.source.name} image=$imageUrl',
        );
      } catch (error, stackTrace) {
        _logPreviewError(
          'image candidate exception source=${link.source.name} '
          'image=$imageUrl',
          error,
          stackTrace,
        );
      }
    }
    _logPreview(
      'all image candidates failed source=${link.source.name} '
      'url=${link.url}',
    );
    return null;
  }

  Future<NoteSubmissionPreview?> _loadImage({
    required String sourceUrl,
    required String imageUrl,
    required bool useFaMediaAuth,
    String? referer,
  }) async {
    final headers = useFaMediaAuth
        ? await FaMediaAuth.headersForUrl(imageUrl) ??
            {'User-Agent': FAHttp.userAgent}
        : {
            'User-Agent': FAHttp.userAgent,
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            if (referer != null) 'Referer': referer,
          };
    final response = await FAHttp.get(
      Uri.parse(imageUrl),
      headers: headers,
      timeout: useFaMediaAuth
          ? null
          : const Duration(seconds: 60),
    );
    final contentType =
        (response.headers['content-type'] ?? '').toLowerCase();
    if (response.statusCode != 200 ||
        response.bodyBytes.isEmpty ||
        contentType.contains('text/html')) {
      _logPreview(
        'image response rejected status=${response.statusCode} '
        'type=$contentType bytes=${response.bodyBytes.length} '
        'image=$imageUrl',
      );
      return null;
    }

    return NoteSubmissionPreview(
      submissionUrl: sourceUrl,
      imageUrl: imageUrl,
      imageBytes: response.bodyBytes,
      extension: noteSubmissionImageExtension(
        imageUrl,
        response.headers['content-type'],
      ),
    );
  }

  Future<bool> _confirmNsfwInOrder(
    Future<bool> Function() confirmNsfw,
  ) {
    final result = Completer<bool>();
    _confirmationQueue = _confirmationQueue.then((_) async {
      try {
        result.complete(await confirmNsfw());
      } catch (_) {
        result.complete(false);
      }
    });
    return result.future;
  }
}

void _logPreview(String message) {
  if (!kDebugMode) {
    return;
  }
  debugPrint('[Note image preview] $message');
}

void _logPreviewError(
  String message,
  Object error,
  StackTrace stackTrace,
) {
  if (!kDebugMode) {
    return;
  }
  debugPrint('[Note image preview] $message error=$error');
  debugPrintStack(
    label: '[Note image preview] stack trace',
    stackTrace: stackTrace,
  );
}
