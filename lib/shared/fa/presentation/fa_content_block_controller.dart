import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:fanotifier/shared/fa/domain/fa_content_block_data.dart';
import 'package:fanotifier/shared/fa/domain/fa_content_block_repository.dart';

class FaContentBlockController extends ChangeNotifier
    with WidgetsBindingObserver {
  FaContentBlockController({required FaContentBlockRepository repository})
      : _repository = repository {
    WidgetsBinding.instance.addObserver(this);
    _resumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  final FaContentBlockRepository _repository;
  final Map<String, bool> _tagChanges = {};
  final LinkedHashMap<String, FaContentBlockData> _resolved = LinkedHashMap();
  final Map<String, Future<void>> _pending = {};
  final Map<String, Set<bool Function()>> _interests = {};
  final Set<String> _failed = {};
  FaContentBlockSnapshot? _snapshot;
  int _revision = 0;
  int _sessionEpoch = 0;
  bool _resumed = true;
  bool _disposed = false;

  int get revision => _revision;
  int get sessionEpoch => _sessionEpoch;

  void acceptItems(
    Iterable<Map<String, dynamic>> items, {
    required int expectedRevision,
  }) {
    for (final item in items) {
      final data = item['contentBlock'] as FaContentBlockData?;
      if (data?.snapshot == null) continue;
      acceptSnapshot(data!.snapshot, expectedRevision: expectedRevision);
      return;
    }
  }

  FaContentBlockData _dataFor(String submissionId, FaContentBlockData data) {
    return data.tagsKnown ? data : _resolved[submissionId] ?? data;
  }

  bool isBlocked(String submissionId, FaContentBlockData data) {
    return _dataFor(submissionId, data).isBlockedBy(_snapshot);
  }

  bool needsTagLookup(String submissionId, FaContentBlockData data) {
    return !_dataFor(submissionId, data).tagsKnown &&
        isBlocked(submissionId, data);
  }

  void acceptSnapshot(
    FaContentBlockSnapshot? snapshot, {
    required int expectedRevision,
  }) {
    if (_disposed || snapshot == null || expectedRevision != _revision) return;
    final blockedTags = Set<String>.from(snapshot.blockedTags);
    final pendingChanges = _tagChanges.length;
    _tagChanges.removeWhere(
      (tag, blocked) => snapshot.blockedTags.contains(tag) == blocked,
    );
    for (final entry in _tagChanges.entries) {
      if (entry.value) {
        blockedTags.add(entry.key);
      } else {
        blockedTags.remove(entry.key);
      }
    }
    if (_snapshot != null && setEquals(_snapshot!.blockedTags, blockedTags)) {
      if (_tagChanges.length != pendingChanges) _revision++;
      return;
    }
    _snapshot = FaContentBlockSnapshot(
      blockedTags: Set<String>.unmodifiable(blockedTags),
    );
    _revision++;
    _failed.clear();
    notifyListeners();
  }

  void setTagBlocked(
    String tagName, {
    required bool blocked,
    required int expectedSessionEpoch,
  }) {
    if (_disposed || expectedSessionEpoch != _sessionEpoch) return;
    final tag = tagName.trim().toLowerCase();
    if (tag.isEmpty) return;
    _tagChanges[tag] = blocked;
    final blockedTags = Set<String>.from(
      _snapshot?.blockedTags ?? const <String>{},
    );
    if (blocked) {
      blockedTags.add(tag);
    } else {
      blockedTags.remove(tag);
    }
    _snapshot = FaContentBlockSnapshot(
      blockedTags: Set<String>.unmodifiable(blockedTags),
    );
    _revision++;
    _failed.clear();
    notifyListeners();
  }

  Future<void> resolveMissingTags(
    String submissionId,
    FaContentBlockData data, {
    required bool Function() isVisible,
  }) async {
    if (_disposed ||
        submissionId.isEmpty ||
        !needsTagLookup(submissionId, data)) {
      return;
    }
    _interests.putIfAbsent(submissionId, () => {}).add(isVisible);
    final pending = _pending[submissionId];
    if (pending != null) return pending;
    if (_failed.contains(submissionId)) return;
    final epoch = _sessionEpoch;
    final expectedRevision = _revision;
    bool cancelled() => _disposed ||
        epoch != _sessionEpoch ||
        !_resumed ||
        !(_interests[submissionId]?.any((visible) => visible()) ?? false);
    final future = _resolve(
      submissionId,
      cancelled,
      epoch,
      expectedRevision,
    );
    _pending[submissionId] = future;
    try {
      await future;
    } finally {
      if (identical(_pending[submissionId], future)) {
        _pending.remove(submissionId);
        if (!_disposed &&
            epoch == _sessionEpoch &&
            _resumed &&
            !_failed.contains(submissionId) &&
            needsTagLookup(submissionId, data) &&
            (_interests[submissionId]?.any((visible) => visible()) ?? false)) {
          notifyListeners();
        }
      }
    }
  }

  Future<void> _resolve(
    String submissionId,
    bool Function() cancelled,
    int epoch,
    int expectedRevision,
  ) async {
    try {
      final data = await _repository.fetchSubmissionTags(
        submissionId: submissionId,
        isCancelled: cancelled,
      );
      if (cancelled() || epoch != _sessionEpoch) return;
      if (data == null || !data.tagsKnown) {
        _markFailed(submissionId);
        return;
      }
      _resolved.remove(submissionId);
      _resolved[submissionId] = data;
      while (_resolved.length > 512) {
        _resolved.remove(_resolved.keys.first);
      }
      _interests.remove(submissionId);
      acceptSnapshot(data.snapshot, expectedRevision: expectedRevision);
      notifyListeners();
    } catch (_) {
      if (!cancelled()) _markFailed(submissionId);
    }
  }

  void _markFailed(String submissionId) {
    _failed.add(submissionId);
    if (_failed.length > 512) _failed.remove(_failed.first);
  }

  void removeLookupInterest(String submissionId, bool Function() isVisible) {
    final interests = _interests[submissionId];
    interests?.remove(isVisible);
    if (interests?.isEmpty ?? false) _interests.remove(submissionId);
  }

  void clear() {
    if (_disposed) return;
    _sessionEpoch++;
    _revision++;
    _snapshot = null;
    _tagChanges.clear();
    _resolved.clear();
    _pending.clear();
    _interests.clear();
    _failed.clear();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionEpoch++;
    _interests.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
