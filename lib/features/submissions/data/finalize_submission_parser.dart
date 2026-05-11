import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:FANotifier/features/submissions/domain/finalize_submission_options.dart';
import 'package:FANotifier/features/submissions/domain/submission_form_option.dart';

FinalizeSubmissionOptions parseFinalizeSubmissionOptions(String html) {
  final document = html_parser.parse(html);

  if (document.querySelector('form[name="login"]') != null) {
    throw Exception('Not authenticated. Please check your login status.');
  }

  final categoryOptions = _parseSelectOptions(document, 'cat');
  _removeDefaultAllFromGroup(categoryOptions, ['Visual Art']);
  categoryOptions.insert(
    0,
    OptionGroup(
      label: '',
      options: [
        Option(label: 'All', value: '1', isDefault: true),
      ],
    ),
  );

  final themeOptions = _parseSelectOptions(document, 'atype');
  _removeDefaultAllFromGroup(themeOptions, ['General Things']);
  themeOptions.insert(
    0,
    OptionGroup(
      label: '',
      options: [
        Option(label: 'All', value: '1', isDefault: true),
      ],
    ),
  );

  return FinalizeSubmissionOptions(
    submissionKey: _parseSubmissionKey(document),
    categoryOptions: categoryOptions,
    themeOptions: themeOptions,
    speciesOptions: _parseSelectOptions(document, 'species'),
    genderOptions: _parseSelectOptions(document, 'gender'),
  );
}

String parseFinalizeSubmissionErrorMessage(String responseBody) {
  final document = html_parser.parse(responseBody);
  final errorElements =
      document.querySelectorAll('.error, .error-message, .alert-danger');
  if (errorElements.isNotEmpty) {
    return errorElements.map((e) => e.text.trim()).join(' ');
  }
  return 'Unknown error occurred.';
}

String _parseSubmissionKey(dom.Document document) {
  final formElement = document.querySelector('form#myform');

  if (formElement == null) {
    throw Exception('Finalize Submission form (id="myform") not found.');
  }

  final keyElement = formElement.querySelector('input[name="key"]');

  if (keyElement != null) {
    final parsedKey = keyElement.attributes['value'] ?? '';
    if (parsedKey.isEmpty) {
      throw Exception('Finalize Submission key value is empty.');
    }
    return parsedKey;
  } else {
    throw Exception('Finalize Submission key input not found within the form.');
  }
}

void _removeDefaultAllFromGroup(
  List<OptionGroup> groups,
  List<String> targetGroupLabels,
) {
  for (final group in groups) {
    if (targetGroupLabels.contains(group.label)) {
      if (group.options.isNotEmpty && group.options[0].label.toLowerCase() == 'all') {
        group.options.removeAt(0);
      }
    }
  }
}

List<OptionGroup> _parseSelectOptions(dom.Document document, String selectName) {
  final optionGroups = <OptionGroup>[];
  final selectElement = document.querySelector('select[name="$selectName"]');

  if (selectElement == null) {
    return optionGroups;
  }

  final directOptions = selectElement.children
      .where((element) => element.localName == 'option')
      .map((option) {
    return Option(
      label: option.text.trim(),
      value: option.attributes['value'] ?? '',
      isDefault: option.attributes.containsKey('selected'),
    );
  }).toList();

  if (directOptions.isNotEmpty) {
    optionGroups.add(OptionGroup(label: '', options: directOptions));
  }

  final optgroups = selectElement.querySelectorAll('optgroup');
  for (final optgroup in optgroups) {
    final groupLabel = optgroup.attributes['label'] ?? '';
    final options = optgroup.querySelectorAll('option').map((option) {
      return Option(
        label: option.text.trim(),
        value: option.attributes['value'] ?? '',
        isDefault: option.attributes.containsKey('selected'),
      );
    }).toList();
    optionGroups.add(OptionGroup(label: groupLabel, options: options));
  }

  return optionGroups;
}
