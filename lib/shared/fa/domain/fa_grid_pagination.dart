class FaLoadedItemIds {
  final Set<String> _ids = <String>{};

  FaUniqueItems<T> prepare<T>(
    Iterable<T> items, {
    required String Function(T) idOf,
  }) {
    final accepted = <T>[];
    final incomingIds = <String>{};
    var receivedCount = 0;
    var duplicateCount = 0;
    for (final item in items) {
      receivedCount++;
      final id = idOf(item);
      if (_ids.contains(id) || !incomingIds.add(id)) {
        duplicateCount++;
        continue;
      }
      accepted.add(item);
    }
    return FaUniqueItems<T>(
      items: accepted,
      ids: incomingIds,
      receivedCount: receivedCount,
      duplicateCount: duplicateCount,
    );
  }

  void commit<T>(FaUniqueItems<T> batch) => _ids.addAll(batch.ids);

  void clear() => _ids.clear();
}

class FaUniqueItems<T> {
  FaUniqueItems({
    required List<T> items,
    required Set<String> ids,
    required this.receivedCount,
    required this.duplicateCount,
  })  : items = List<T>.unmodifiable(items),
        ids = Set<String>.unmodifiable(ids);

  final List<T> items;
  final Set<String> ids;
  final int receivedCount;
  final int duplicateCount;

  bool get duplicateOnly => receivedCount > 0 && items.isEmpty;
}

class FaGridPaginationProgress {
  static const int maxDuplicateOnlyPages = 3;

  final Set<String> _completedCursors = <String>{};
  int _duplicateOnlyPages = 0;

  bool get paused => _duplicateOnlyPages >= maxDuplicateOnlyPages;

  bool hasCompleted(String cursor) => _completedCursors.contains(cursor);

  void record({required String cursor, required bool duplicateOnly}) {
    _completedCursors.add(cursor);
    _duplicateOnlyPages = duplicateOnly ? _duplicateOnlyPages + 1 : 0;
  }

  void resume() => _duplicateOnlyPages = 0;

  void clear() {
    _completedCursors.clear();
    resume();
  }
}
