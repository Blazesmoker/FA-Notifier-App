import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';

enum FaContactValidationRule {
  url,
  username,
  userId,
  stoatUsername,
}

class FaContactField {
  const FaContactField({
    required this.name,
    required this.label,
    required this.placeholder,
    required this.inputType,
    required this.validationRules,
    this.maxLength,
    this.min,
    this.max,
    this.verificationUrlTemplate,
    this.iconUri,
  });

  final String name;
  final String label;
  final String placeholder;
  final String inputType;
  final List<FaContactValidationRule> validationRules;
  final int? maxLength;
  final int? min;
  final int? max;
  final String? verificationUrlTemplate;
  final Uri? iconUri;
}

class FaContactSection {
  const FaContactSection({
    required this.title,
    required this.fields,
    this.description,
  });

  final String title;
  final String? description;
  final List<FaContactField> fields;
}

class FaContactsFormSnapshot {
  const FaContactsFormSnapshot({
    required this.form,
    required this.sections,
  });

  final FaSettingsFormSnapshot form;
  final List<FaContactSection> sections;

  FaContactsFormSnapshot withForm(FaSettingsFormSnapshot form) {
    return FaContactsFormSnapshot(
      form: form,
      sections: sections,
    );
  }
}
