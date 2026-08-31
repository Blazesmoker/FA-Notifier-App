import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/settings/domain/fur_affinity_profile_management_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';

class ProfileInfoController extends ChangeNotifier {
  ProfileInfoController(this._repository);

  static const textFields = <String>{
    'profileinfo',
    'display_name',
    'custom_title',
    'species',
    'music',
    'favoritemovie',
    'favoritegame',
    'favoriteplatform',
    'favoriteartist',
    'favoriteanimal',
    'favoritefood',
    'favoritewebsite',
    'quote',
    'blocklist',
    'submissionfooter',
    'journalheader',
    'journalfooter',
  };
  static const selectFields = <String>{
    'mood',
    'featured',
    'profile_pic',
    'hide_blocked_user_content',
  };

  final FurAffinitySettingsRepository _repository;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _values = {};
  final Map<String, String> _initial = {};
  FaProfileInfoSnapshot? _snapshot;
  Object? loadError;
  bool loading = true;
  bool saving = false;
  bool didSave = false;
  bool _disposed = false;
  final ValueNotifier<bool> _dirtyNotifier = ValueNotifier<bool>(false);

  FaProfileInfoSnapshot? get snapshot => _snapshot;

  ValueListenable<bool> get dirtyListenable => _dirtyNotifier;

  bool get dirty {
    for (final name in textFields) {
      if ((_controllers[name]?.text ?? '') != (_initial[name] ?? '')) return true;
    }
    for (final name in selectFields) {
      if ((_values[name] ?? '') != (_initial[name] ?? '')) return true;
    }
    return false;
  }

  TextEditingController controller(String name) => _controllers[name]!;
  String value(String name) => _values[name] ?? '';
  FaFormFieldSnapshot? field(String name) => _snapshot?.form.field(name);

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final snapshot = await _repository.loadProfileInfo();
      if (_disposed) return;
      _apply(snapshot);
      loading = false;
      notifyListeners();
    } catch (error) {
      if (_disposed) return;
      loading = false;
      loadError = error;
      notifyListeners();
    }
  }

  void setValue(String name, String value) {
    _values[name] = value;
    _updateDirtyState();
    notifyListeners();
  }

  Future<FaSettingsMutationResult?> save() async {
    final snapshot = _snapshot;
    if (snapshot == null || !dirty || saving) return null;
    saving = true;
    notifyListeners();
    final values = <String, String?>{};
    for (final name in textFields) {
      if (snapshot.form.field(name)?.enabled ?? false) {
        values[name] = _controllers[name]?.text ?? '';
      }
    }
    for (final name in selectFields) {
      if (snapshot.form.field(name)?.enabled ?? false) {
        values[name] = _values[name] ?? '';
      }
    }
    final result = await _repository.saveProfileInfo(form: snapshot, values: values);
    if (_disposed) return result;
    if (result.success) {
      final updated = FaProfileInfoSnapshot(
        result.returnedForm ?? snapshot.form.withAppliedValues(values),
      );
      _apply(updated);
      didSave = true;
    }
    saving = false;
    notifyListeners();
    return result;
  }

  void _apply(FaProfileInfoSnapshot snapshot) {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _values.clear();
    _initial.clear();
    _snapshot = snapshot;
    for (final name in textFields) {
      final value = snapshot.form.field(name)?.value ?? '';
      _controllers[name] = TextEditingController(text: value)
        ..addListener(_changed);
      _initial[name] = value;
    }
    for (final name in selectFields) {
      final value = snapshot.form.field(name)?.value ?? '';
      _values[name] = value;
      _initial[name] = value;
    }
    _updateDirtyState();
  }

  void _changed() {
    if (!_disposed) _updateDirtyState();
  }

  void _updateDirtyState() {
    if (!_disposed) {
      final value = dirty;
      if (_dirtyNotifier.value != value) _dirtyNotifier.value = value;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _dirtyNotifier.dispose();
    super.dispose();
  }
}
