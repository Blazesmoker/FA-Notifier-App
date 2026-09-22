class NoteArrivalPolicy {
  NoteArrivalPolicy(Iterable<String> knownIds)
      : _knownIds = knownIds.toSet() {
    for (final id in _knownIds) {
      final value = BigInt.tryParse(id);
      if (value != null && value > BigInt.zero &&
          (_latestKnownId == null || value > _latestKnownId!)) {
        _latestKnownId = value;
      }
    }
  }

  final Set<String> _knownIds;
  BigInt? _latestKnownId;

  bool isNewArrival(String id) {
    if (_knownIds.contains(id)) return false;
    final value = BigInt.tryParse(id);
    final boundary = _latestKnownId;
    return value != null && boundary != null && value > boundary;
  }
}
