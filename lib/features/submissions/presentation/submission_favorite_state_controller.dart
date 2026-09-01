import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';

class SubmissionFavoriteStateController extends ChangeNotifier {
  SubmissionFavoriteStateController({
    required SubmissionFavoriteRepository repository,
    this.debounceDuration = const Duration(seconds: 3),
  }) : _repository = repository;

  final SubmissionFavoriteRepository _repository;
  final Duration debounceDuration;
  final Map<String, _SubmissionFavoriteEntry> _entries = {};
  int _sessionGeneration = 0;
  bool _disposed = false;

  bool valueFor(String submissionId, bool fallback) {
    return _entries[submissionId]?.desiredState ?? fallback;
  }

  bool toggle({
    required String submissionId,
    required bool fallbackIsFavorite,
    String? favUrl,
    String? unfavUrl,
    bool? sfwEnabled,
  }) {
    final knownState = _entries[submissionId]?.desiredState ??
        _stateFromLinks(favUrl: favUrl, unfavUrl: unfavUrl) ??
        fallbackIsFavorite;
    final next = !knownState;
    setFavoriteState(
      submissionId: submissionId,
      isFavorite: next,
      fallbackIsFavorite: knownState,
      favUrl: favUrl,
      unfavUrl: unfavUrl,
      sfwEnabled: sfwEnabled,
    );
    return next;
  }

  void setFavoriteState({
    required String submissionId,
    required bool isFavorite,
    required bool fallbackIsFavorite,
    String? favUrl,
    String? unfavUrl,
    bool? sfwEnabled,
  }) {
    if (_disposed || submissionId.isEmpty) return;
    final entry = _entries.putIfAbsent(
      submissionId,
      () => _SubmissionFavoriteEntry(
        confirmedState: fallbackIsFavorite,
        desiredState: fallbackIsFavorite,
      ),
    );
    if (favUrl != null && favUrl.isNotEmpty) entry.favUrl = favUrl;
    if (unfavUrl != null && unfavUrl.isNotEmpty) entry.unfavUrl = unfavUrl;
    if (sfwEnabled != null) entry.sfwEnabled = sfwEnabled;
    entry.desiredState = isFavorite;
    entry.timer?.cancel();
    entry.timer = null;
    if (!entry.inFlight && entry.desiredState != entry.confirmedState) {
      _schedule(submissionId, entry, debounceDuration);
    }
    _notifyChanged();
  }

  void clear() {
    _sessionGeneration++;
    for (final entry in _entries.values) {
      entry.timer?.cancel();
    }
    _entries.clear();
    _notifyChanged();
  }

  void _schedule(
    String submissionId,
    _SubmissionFavoriteEntry entry,
    Duration delay,
  ) {
    entry.timer?.cancel();
    entry.timer = Timer(delay, () {
      entry.timer = null;
      unawaited(_process(submissionId, entry));
    });
  }

  Future<void> _process(
    String submissionId,
    _SubmissionFavoriteEntry entry,
  ) async {
    if (_disposed ||
        entry.inFlight ||
        _entries[submissionId] != entry ||
        entry.desiredState == entry.confirmedState) {
      return;
    }
    final generation = _sessionGeneration;
    final attemptedState = entry.desiredState;
    entry.inFlight = true;
    _notifyChanged();

    SubmissionFavoriteMutationResult result;
    try {
      result = await _repository.setFavoriteState(
        submissionId: submissionId,
        isFavorite: attemptedState,
        favUrl: entry.favUrl,
        unfavUrl: entry.unfavUrl,
        sfwEnabled: entry.sfwEnabled,
      );
    } catch (_) {
      result = SubmissionFavoriteMutationResult(
        success: false,
        confirmedState: !attemptedState,
        changed: false,
      );
    }
    if (_disposed ||
        generation != _sessionGeneration ||
        _entries[submissionId] != entry) {
      return;
    }

    entry.inFlight = false;
    entry.confirmedState = result.confirmedState;
    if (!result.success && entry.desiredState == attemptedState) {
      entry.desiredState = result.confirmedState;
    }
    if (result.success && result.changed) {
      entry.favUrl = null;
      entry.unfavUrl = null;
    }
    if (entry.desiredState != entry.confirmedState) {
      _schedule(submissionId, entry, Duration.zero);
    }
    _notifyChanged();
  }

  void _notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  bool? _stateFromLinks({String? favUrl, String? unfavUrl}) {
    final hasFavUrl = favUrl != null && favUrl.isNotEmpty;
    final hasUnfavUrl = unfavUrl != null && unfavUrl.isNotEmpty;
    if (hasUnfavUrl && !hasFavUrl) return true;
    if (hasFavUrl && !hasUnfavUrl) return false;
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _entries.values) {
      entry.timer?.cancel();
    }
    _entries.clear();
    super.dispose();
  }
}

class _SubmissionFavoriteEntry {
  _SubmissionFavoriteEntry({
    required this.confirmedState,
    required this.desiredState,
  });

  bool confirmedState;
  bool desiredState;
  bool inFlight = false;
  String? favUrl;
  String? unfavUrl;
  bool? sfwEnabled;
  Timer? timer;
}
