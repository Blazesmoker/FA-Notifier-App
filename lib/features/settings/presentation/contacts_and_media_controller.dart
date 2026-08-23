import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/settings/domain/fur_affinity_contacts_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_repository.dart';

enum FaContactValidationStatus {
  none,
  valid,
  invalid,
}

class ContactsAndMediaController extends ChangeNotifier {
  ContactsAndMediaController(this._repository);

  final FurAffinitySettingsRepository _repository;
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, String> _initialValues = <String, String>{};

  FaContactsFormSnapshot? _form;
  Object? _loadError;
  bool _loading = true;
  bool _saving = false;
  bool _applying = false;
  bool _disposed = false;
  bool _didSave = false;

  FaContactsFormSnapshot? get form => _form;
  Object? get loadError => _loadError;
  bool get loading => _loading;
  bool get saving => _saving;
  bool get didSave => _didSave;

  bool get dirty {
    for (final entry in _controllers.entries) {
      if (entry.value.text != (_initialValues[entry.key] ?? '')) return true;
    }
    return false;
  }

  bool get valid {
    final snapshot = _form;
    if (snapshot == null) return false;
    for (final section in snapshot.sections) {
      for (final field in section.fields) {
        if (enabled(field.name) &&
            _isFieldChanged(field.name) &&
            !_isFieldValid(field)) {
          return false;
        }
      }
    }
    return true;
  }

  TextEditingController controllerFor(String name) {
    return _controllers[name]!;
  }

  bool enabled(String name) => _form?.form.field(name)?.enabled ?? false;

  Future<void> load() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final form = await _repository.loadContacts();
      if (_disposed) return;
      _applyLoadedForm(form);
      _loading = false;
      notifyListeners();
    } catch (error) {
      if (_disposed) return;
      _loading = false;
      _loadError = error;
      notifyListeners();
    }
  }

  Future<FaSettingsMutationResult?> save() async {
    final snapshot = _form;
    if (snapshot == null || !dirty || !valid || _saving) return null;
    _saving = true;
    notifyListeners();
    final values = <String, String?>{};
    for (final section in snapshot.sections) {
      for (final field in section.fields) {
        if (enabled(field.name)) {
          values[field.name] = _controllers[field.name]?.text ?? '';
        }
      }
    }
    final result = await _repository.saveContacts(
      form: snapshot,
      values: values,
    );
    if (_disposed) return result;
    if (result.success) {
      final returnedForm = result.returnedForm ??
          snapshot.form.withAppliedValues(values);
      _applySavedForm(snapshot.withForm(returnedForm));
      _didSave = true;
    }
    _saving = false;
    notifyListeners();
    return result;
  }

  FaContactValidationStatus validationStatus(FaContactField field) {
    final value = _controllers[field.name]?.text.trim() ?? '';
    if (!enabled(field.name) ||
        value.isEmpty ||
        !_hasVisibleValidation(field)) {
      return FaContactValidationStatus.none;
    }
    return _isFieldValid(field)
        ? FaContactValidationStatus.valid
        : FaContactValidationStatus.invalid;
  }

  Uri? verificationUri(FaContactField field) {
    if (validationStatus(field) != FaContactValidationStatus.valid) {
      return null;
    }
    final value = _controllers[field.name]?.text.trim() ?? '';
    final template = field.verificationUrlTemplate;
    Uri? uri;
    if (template != null) {
      uri = Uri.tryParse(
        template.replaceAll('%username%', Uri.encodeComponent(value)),
      );
    } else if (field.validationRules.contains(FaContactValidationRule.url)) {
      uri = Uri.tryParse(value);
    }
    if (uri == null ||
        (uri.scheme != 'https' &&
            uri.scheme != 'http' &&
            uri.scheme != 'mailto')) {
      return null;
    }
    return uri;
  }

  bool _hasVisibleValidation(FaContactField field) {
    return field.validationRules.isNotEmpty || field.inputType == 'email';
  }

  bool _isFieldChanged(String name) {
    return (_controllers[name]?.text ?? '') != (_initialValues[name] ?? '');
  }

  bool _isFieldValid(FaContactField field) {
    final value = _controllers[field.name]?.text.trim() ?? '';
    if (value.isEmpty) return true;
    if (field.maxLength != null && value.length > field.maxLength!) {
      return false;
    }
    if (field.inputType == 'email' &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      return false;
    }
    for (final rule in field.validationRules) {
      switch (rule) {
        case FaContactValidationRule.url:
          final uri = Uri.tryParse(value);
          if (uri == null ||
              (uri.scheme != 'https' && uri.scheme != 'http') ||
              uri.host.isEmpty) {
            return false;
          }
          break;
        case FaContactValidationRule.username:
          if (RegExp(r'[\\/?&]').hasMatch(value)) return false;
          break;
        case FaContactValidationRule.userId:
          if (!RegExp(r'^\d+$').hasMatch(value)) return false;
          final number = int.tryParse(value);
          if (number == null ||
              (field.min != null && number < field.min!) ||
              (field.max != null && number > field.max!)) {
            return false;
          }
          break;
        case FaContactValidationRule.stoatUsername:
          if (!RegExp(r'^.{2,32}#\d{4}$').hasMatch(value)) return false;
          break;
      }
    }
    return true;
  }

  void _applyLoadedForm(FaContactsFormSnapshot snapshot) {
    _applying = true;
    for (final controller in _controllers.values) {
      controller.removeListener(_handleChanged);
      controller.dispose();
    }
    _controllers.clear();
    _initialValues.clear();
    _form = snapshot;
    for (final section in snapshot.sections) {
      for (final field in section.fields) {
        final value = snapshot.form.field(field.name)?.value ?? '';
        final controller = TextEditingController(text: value)
          ..addListener(_handleChanged);
        _controllers[field.name] = controller;
        _initialValues[field.name] = value;
      }
    }
    _applying = false;
  }

  void _applySavedForm(FaContactsFormSnapshot snapshot) {
    _applying = true;
    _form = snapshot;
    for (final section in snapshot.sections) {
      for (final field in section.fields) {
        final value = snapshot.form.field(field.name)?.value ?? '';
        _controllers[field.name]?.text = value;
        _initialValues[field.name] = value;
      }
    }
    _applying = false;
  }

  void _handleChanged() {
    if (!_applying && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final controller in _controllers.values) {
      controller.removeListener(_handleChanged);
      controller.dispose();
    }
    super.dispose();
  }
}
