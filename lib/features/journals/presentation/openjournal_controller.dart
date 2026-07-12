import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:FANotifier/features/journals/data/journal_action_service.dart';
import 'package:FANotifier/features/journals/data/journal_comment_service.dart';
import 'package:FANotifier/features/journals/data/journal_deletion_coordinator.dart';
import 'package:FANotifier/features/journals/data/journal_link_parser.dart';
import 'package:FANotifier/features/journals/data/openjournal_api_service.dart';
import 'package:FANotifier/features/journals/data/openjournal_load_coordinator.dart';
import 'package:FANotifier/features/journals/data/openjournal_repository_impl.dart';
import 'package:FANotifier/features/journals/domain/journal_deletion_result.dart';
import 'package:FANotifier/features/journals/domain/journal_optimistic_comment.dart';
import 'package:FANotifier/features/journals/domain/journal_publication_time_parser.dart';
import 'package:FANotifier/features/journals/domain/openjournal_fetch_result.dart';
import 'package:FANotifier/features/journals/domain/openjournal_load_result.dart';

class OpenJournalController extends ChangeNotifier {
  OpenJournalController({
    required this.journalId,
    OpenJournalApiService? api,
    OpenJournalLoadCoordinator? loadCoordinator,
    JournalActionService? actionService,
    JournalDeletionCoordinator? deletionCoordinator,
    JournalCommentService? commentService,
  }) {
    final resolvedApi = api ?? OpenJournalApiService();
    final resolvedActionService = actionService ?? const JournalActionService();
    _loadCoordinator = loadCoordinator ??
        OpenJournalLoadCoordinator(
          repository: OpenJournalRepositoryImpl(api: resolvedApi),
        );
    _actionService = resolvedActionService;
    _deletionCoordinator = deletionCoordinator ??
        JournalDeletionCoordinator(
          api: resolvedApi,
          actionService: resolvedActionService,
        );
    _commentService = commentService ?? JournalCommentService();
  }

  final String journalId;
  late final OpenJournalLoadCoordinator _loadCoordinator;
  late final JournalActionService _actionService;
  late final JournalDeletionCoordinator _deletionCoordinator;
  late final JournalCommentService _commentService;

  String? _profileImageUrl;
  String? _submissionTitle;
  String? _submissionDescription;
  DateTime? _publicationTime;
  String? _publicationTimeRaw;
  int _commentsCount = 0;
  List<Map<String, dynamic>> _comments = [];
  String? _authorDisplayName;
  String? _authorUserName;
  String? _authorSymbol;
  String? _authorUserTitle;
  bool _isJournalClassic = false;
  String? _watchLink;
  String? _unwatchLink;
  bool _isWatching = false;
  String? _favoriteLink;
  String? _unfavoriteLink;
  bool _isFavorited = false;
  String? _blockLink;
  String? _unblockLink;
  bool _isBlocked = false;
  String? _fullViewImageUrl;
  String? _fileLink;
  bool _isLoading = true;
  bool _isOwner = false;
  String? _deleteLink;
  String? _category;
  String? _type;
  String? _species;
  String? _gender;
  List<String> _keywords = [];
  bool _disposed = false;

  String? get profileImageUrl => _profileImageUrl;
  String? get submissionTitle => _submissionTitle;
  String? get submissionDescription => _submissionDescription;
  DateTime? get publicationTime => _publicationTime;
  String? get publicationTimeRaw => _publicationTimeRaw;
  int get commentsCount => _commentsCount;
  List<Map<String, dynamic>> get comments => _comments;
  String? get authorDisplayName => _authorDisplayName;
  String? get authorUserName => _authorUserName;
  String? get authorSymbol => _authorSymbol;
  String? get authorUserTitle => _authorUserTitle;
  bool get isJournalClassic => _isJournalClassic;
  String? get watchLink => _watchLink;
  String? get unwatchLink => _unwatchLink;
  bool get isWatching => _isWatching;
  String? get favoriteLink => _favoriteLink;
  String? get unfavoriteLink => _unfavoriteLink;
  bool get isFavorited => _isFavorited;
  String? get blockLink => _blockLink;
  String? get unblockLink => _unblockLink;
  bool get isBlocked => _isBlocked;
  String? get fullViewImageUrl => _fullViewImageUrl;
  String? get fileLink => _fileLink;
  bool get isLoading => _isLoading;
  bool get isOwner => _isOwner;
  String? get category => _category;
  String? get type => _type;
  String? get species => _species;
  String? get gender => _gender;
  List<String> get keywords => _keywords;

  Future<OpenJournalLoadResult> load() async {
    try {
      final loadResult = await _loadCoordinator.load(journalId);
      if (_disposed) {
        return loadResult;
      }
      if (loadResult.isUnavailable) {
        return loadResult;
      }

      final result = loadResult.journal;
      _applyJournal(result);

      if (_publicationTime == null && _publicationTimeRaw != null) {
        _parsePublicationTime(_publicationTimeRaw!);
      }

      if (result.commentBodies.isNotEmpty) {
        _comments = result.commentBodies;
        _commentsCount = result.commentsCount;
        _notifyChanged();
      } else if (loadResult.shouldFetchFallbackComments) {
        unawaited(_fetchFallbackComments(result.submissionDescription!));
      }

      return loadResult;
    } catch (_) {
      _isLoading = false;
      _notifyChanged();
      rethrow;
    }
  }

  Future<JournalDeletionResult> deleteJournal() {
    return _deletionCoordinator.delete(
      journalId: journalId,
      currentDeleteLink: _deleteLink,
      onDeleteLinkResolved: (resolvedDeleteLink) {
        _deleteLink = resolvedDeleteLink;
        _notifyChanged();
      },
    );
  }

  Future<int?> updateCommentVisibility(String link) {
    return _actionService.updateCommentVisibility(link);
  }

  Future<bool> submitComment(String message) {
    return _commentService.submitComment(
      message: message,
      journalId: journalId,
    );
  }

  void addOptimisticComment(String text, DateTime now) {
    _comments.add(buildOptimisticJournalComment(text: text, now: now));
    _commentsCount++;
    _notifyChanged();
  }

  String getFullLink(String truncatedUrl, {String? htmlSource}) {
    final source = htmlSource ?? _submissionDescription;
    if (source == null) return truncatedUrl;
    return findFullShortenedJournalLink(source, truncatedUrl) ?? truncatedUrl;
  }

  String? get formattedPublicationTime {
    final raw = _publicationTimeRaw;
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    final publicationTime = _publicationTime;
    if (publicationTime == null) return null;
    return DateFormat.yMMMd().add_jm().format(publicationTime.toLocal());
  }

  void _applyJournal(OpenJournalFetchResult result) {
    _isJournalClassic = result.isJournalClassic;
    _isOwner = result.ownerEditLink != null;
    _profileImageUrl = result.profileImageUrl;
    _authorDisplayName = result.displayName;
    _authorUserName = result.authorSlug;
    _authorSymbol = result.symbol;
    _authorUserTitle = result.userTitle;
    _submissionDescription = result.submissionDescription;
    _submissionTitle = result.title;
    _publicationTime = result.dateTime;
    _publicationTimeRaw = result.dateTimeRaw;
    _commentsCount = result.commentsCount;
    _favoriteLink = result.favoriteLink;
    _unfavoriteLink = result.unfavoriteLink;
    _isFavorited = result.isFavorited;
    _watchLink = result.watchLink;
    _unwatchLink = result.unwatchLink;
    _isWatching = result.isWatching;
    _blockLink = result.blockLink;
    _unblockLink = result.unblockLink;
    _isBlocked = result.isBlocked;
    _category = result.category;
    _type = result.type;
    _species = result.species;
    _gender = result.gender;
    _keywords = result.keywords;
    _fullViewImageUrl = result.fullViewImageUrl;
    _fileLink = result.fileLink;
    _deleteLink = result.deleteLink;
    _isLoading = false;
    _notifyChanged();
  }

  Future<void> _fetchFallbackComments(String body) async {
    try {
      final comments = await _loadCoordinator.fetchFallbackComments(body);
      if (_disposed) return;
      _comments = comments;
      _notifyChanged();
    } catch (e) {
      debugPrint('Failed to parse comments: $e');
    }
  }

  void _parsePublicationTime(String rawTime) {
    try {
      final parsed = parseJournalPublicationTime(
        rawTime,
        applyDstCorrection: false,
      );
      if (parsed != null) {
        _publicationTime = parsed;
      }
    } catch (e, stackTrace) {
      debugPrint('Error parsing publication time: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _notifyChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
