import 'dart:async';

import 'package:FANotifier/core/fa/fa_media_auth.dart';
import 'package:FANotifier/core/network/fa_http.dart';
import 'package:FANotifier/core/preferences/sfw_mode_preference.dart';
import 'package:FANotifier/features/notes/data/note_submission_preview_parser.dart';
import 'package:FANotifier/features/notes/domain/note_submission_preview.dart';
import 'package:FANotifier/features/notes/domain/note_submission_preview_repository.dart';
import 'package:FANotifier/features/submissions/domain/openpost_repository.dart';

class NoteSubmissionPreviewRepositoryImpl
    implements NoteSubmissionPreviewRepository {
  NoteSubmissionPreviewRepositoryImpl({
    required OpenPostRepository openPostRepository,
    SfwModePreference sfwModePreference = const SfwModePreference(),
  })  : _openPostRepository = openPostRepository,
        _sfwModePreference = sfwModePreference;

  final OpenPostRepository _openPostRepository;
  final SfwModePreference _sfwModePreference;
  final Map<String, NoteSubmissionPreview> _cache = {};
  final Map<String, Future<NoteSubmissionPreview?>> _inFlight = {};
  Future<void> _confirmationQueue = Future<void>.value();

  @override
  Future<NoteSubmissionPreview?> loadPreview(
    String submissionUrl, {
    required Future<bool> Function() confirmNsfw,
  }) async {
    final normalizedUrl = _normalizeSubmissionUrl(submissionUrl);
    final cached = _cache[normalizedUrl];
    if (cached != null) return cached;
    final pending = _inFlight[normalizedUrl];
    if (pending != null) return pending;

    final future = _loadPreview(normalizedUrl, confirmNsfw);
    _inFlight[normalizedUrl] = future;
    try {
      final preview = await future;
      if (preview != null) _cache[normalizedUrl] = preview;
      return preview;
    } finally {
      _inFlight.remove(normalizedUrl);
    }
  }

  Future<NoteSubmissionPreview?> _loadPreview(
    String submissionUrl,
    Future<bool> Function() confirmNsfw,
  ) async {
    final sfwEnabled = await _sfwModePreference.loadSfwEnabled();
    var page = await _openPostRepository.fetchPage(
      url: submissionUrl,
      sfwEnabled: sfwEnabled,
      nsfwAllowed: false,
    );
    if (sfwEnabled &&
        (page.matureContentWarning || page.oldMatureImageError)) {
      if (!await _confirmNsfwInOrder(confirmNsfw)) return null;
      page = await _openPostRepository.fetchPage(
        url: submissionUrl,
        sfwEnabled: sfwEnabled,
        nsfwAllowed: true,
        skipSfw: true,
      );
    }
    if (page.statusCode != 200 || !page.isHtml) return null;

    final imageUrl =
        parseNoteSubmissionHighQualityImageUrl(page.bodyBytes);
    if (imageUrl == null) return null;
    final response = await FAHttp.get(
      Uri.parse(imageUrl),
      headers: await FaMediaAuth.headersForUrl(imageUrl) ??
          {'User-Agent': FAHttp.userAgent},
    );
    final contentType =
        (response.headers['content-type'] ?? '').toLowerCase();
    if (response.statusCode != 200 ||
        response.bodyBytes.isEmpty ||
        contentType.contains('text/html')) {
      return null;
    }

    return NoteSubmissionPreview(
      submissionUrl: submissionUrl,
      imageUrl: imageUrl,
      imageBytes: response.bodyBytes,
      extension: noteSubmissionImageExtension(
        imageUrl,
        response.headers['content-type'],
      ),
    );
  }

  String _normalizeSubmissionUrl(String url) {
    final normalized = FaMediaAuth.normalizeUrl(url);
    final uri = Uri.parse(normalized);
    return uri.replace(fragment: '', query: '').toString();
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
