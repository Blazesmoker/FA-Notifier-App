class FaFormOption {
  const FaFormOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

class FaFormFieldSnapshot {
  const FaFormFieldSnapshot({
    required this.name,
    required this.type,
    required this.value,
    required this.enabled,
    required this.checked,
    this.options = const <FaFormOption>[],
    this.min,
    this.max,
    this.maxLength,
  });

  final String name;
  final String type;
  final String value;
  final bool enabled;
  final bool checked;
  final List<FaFormOption> options;
  final String? min;
  final String? max;
  final int? maxLength;

  FaFormFieldSnapshot copyWith({
    String? value,
    bool? checked,
  }) {
    return FaFormFieldSnapshot(
      name: name,
      type: type,
      value: value ?? this.value,
      enabled: enabled,
      checked: checked ?? this.checked,
      options: options,
      min: min,
      max: max,
      maxLength: maxLength,
    );
  }
}

class FaSettingsFormSnapshot {
  FaSettingsFormSnapshot({
    required this.actionUri,
    required Map<String, String> basePayload,
    required Map<String, FaFormFieldSnapshot> fields,
    this.faPlusIconUri,
  })  : basePayload = Map<String, String>.unmodifiable(basePayload),
        fields = Map<String, FaFormFieldSnapshot>.unmodifiable(fields);

  final Uri actionUri;
  final Map<String, String> basePayload;
  final Map<String, FaFormFieldSnapshot> fields;
  final Uri? faPlusIconUri;

  FaFormFieldSnapshot? field(String name) => fields[name];

  Map<String, String> buildPayload(Map<String, String?> values) {
    final payload = Map<String, String>.from(basePayload);
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null) {
        payload.remove(entry.key);
      } else {
        payload[entry.key] = value;
      }
    }
    return payload;
  }

  FaSettingsFormSnapshot withAppliedValues(Map<String, String?> values) {
    final updatedFields = Map<String, FaFormFieldSnapshot>.from(fields);
    for (final entry in values.entries) {
      final field = updatedFields[entry.key];
      if (field == null) continue;
      if (field.type == 'checkbox') {
        updatedFields[entry.key] = field.copyWith(
          checked: entry.value != null,
        );
      } else if (entry.value != null) {
        updatedFields[entry.key] = field.copyWith(value: entry.value);
      }
    }
    return FaSettingsFormSnapshot(
      actionUri: actionUri,
      basePayload: buildPayload(values),
      fields: updatedFields,
      faPlusIconUri: faPlusIconUri,
    );
  }
}

class FaSettingsMutationResult {
  const FaSettingsMutationResult({
    required this.success,
    this.statusCode,
    this.message,
    this.returnedForm,
  });

  final bool success;
  final int? statusCode;
  final String? message;
  final FaSettingsFormSnapshot? returnedForm;
}

class FaSettingsRequestException implements Exception {
  const FaSettingsRequestException(
    this.message, {
    this.statusCode,
  });

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
