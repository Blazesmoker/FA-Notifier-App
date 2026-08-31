import 'package:flutter/foundation.dart';

import 'package:fanotifier/features/profile/domain/shout.dart';

class UserProfileShoutSelectionController {
  final ValueNotifier<bool> selectionMode = ValueNotifier<bool>(false);
  final ValueNotifier<int> selectedCount = ValueNotifier<int>(0);
  final Set<String> _selectedIds = <String>{};
  final Map<String, ValueNotifier<bool>> _selectionById =
      <String, ValueNotifier<bool>>{};

  bool get isSelectionMode => selectionMode.value;

  Set<String> get selectedIds => Set<String>.unmodifiable(_selectedIds);

  String selectionId(Shout shout) {
    if (shout.id.isNotEmpty) {
      return shout.id;
    }
    return '${shout.sourcePage}:${shout.profileNickname}:${shout.popupDateFull}:${shout.text.hashCode}';
  }

  ValueListenable<bool> selectionFor(Shout shout) {
    final id = selectionId(shout);
    return _selectionById.putIfAbsent(
      id,
      () => ValueNotifier<bool>(_selectedIds.contains(id)),
    );
  }

  bool isSelected(Shout shout) => _selectedIds.contains(selectionId(shout));

  void toggleMode() {
    final enabled = !selectionMode.value;
    if (!enabled) {
      _clearSelection();
    }
    selectionMode.value = enabled;
  }

  void exitSelectionMode() {
    if (!selectionMode.value) {
      return;
    }
    _clearSelection();
    selectionMode.value = false;
  }

  void toggle(Shout shout) {
    if (!selectionMode.value) {
      return;
    }
    final id = selectionId(shout);
    final selected = !_selectedIds.contains(id);
    if (selected) {
      _selectedIds.add(id);
    } else {
      _selectedIds.remove(id);
    }
    _selectionById
        .putIfAbsent(id, () => ValueNotifier<bool>(!selected))
        .value = selected;
    selectedCount.value = _selectedIds.length;
  }

  List<Shout> selectedShouts(Iterable<Shout> shouts) {
    return shouts.where(isSelected).toList(growable: false);
  }

  void reconcile(Iterable<Shout> shouts) {
    final validIds = shouts.map(selectionId).toSet();
    final removedIds = _selectedIds.difference(validIds);
    if (removedIds.isEmpty) {
      return;
    }
    for (final id in removedIds) {
      _selectedIds.remove(id);
      final notifier = _selectionById[id];
      if (notifier != null) {
        notifier.value = false;
      }
    }
    selectedCount.value = _selectedIds.length;
  }

  void _clearSelection() {
    if (_selectedIds.isEmpty) {
      return;
    }
    final selectedIds = _selectedIds.toList(growable: false);
    _selectedIds.clear();
    for (final id in selectedIds) {
      final notifier = _selectionById[id];
      if (notifier != null) {
        notifier.value = false;
      }
    }
    selectedCount.value = 0;
  }

  void dispose() {
    selectionMode.dispose();
    selectedCount.dispose();
    for (final notifier in _selectionById.values) {
      notifier.dispose();
    }
    _selectionById.clear();
    _selectedIds.clear();
  }
}
