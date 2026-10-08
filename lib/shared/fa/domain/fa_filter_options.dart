class FaFilterOption {
  const FaFilterOption({
    required this.field,
    required this.value,
    required this.label,
  });

  final String field;
  final String value;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is FaFilterOption &&
      field == other.field &&
      value == other.value &&
      label == other.label;

  @override
  int get hashCode => Object.hash(field, value, label);
}

class FaFilterOptions {
  FaFilterOptions(Map<String, List<FaFilterOption>> groups)
      : groups = Map.unmodifiable({
          for (final entry in groups.entries)
            entry.key: List<FaFilterOption>.unmodifiable(entry.value),
        });

  final Map<String, List<FaFilterOption>> groups;

  List<FaFilterOption> operator [](String group) => groups[group] ?? const [];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FaFilterOptions || groups.length != other.groups.length) {
      return false;
    }
    for (final entry in groups.entries) {
      final options = other.groups[entry.key];
      if (options == null || options.length != entry.value.length) return false;
      for (var index = 0; index < options.length; index++) {
        if (options[index] != entry.value[index]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
        groups.entries.map(
          (entry) => Object.hash(entry.key, Object.hashAll(entry.value)),
        ),
      );
}
