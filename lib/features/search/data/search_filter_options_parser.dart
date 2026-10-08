import 'package:html/dom.dart';

import 'package:fanotifier/features/search/domain/search_filter_options.dart';
import 'package:fanotifier/shared/fa/domain/fa_filter_options.dart';
import 'package:fanotifier/shared/fa/domain/fa_page_settings.dart';

FaFilterOptions? parseSearchFilterDocument(Document document) {
  var form = document.querySelector('select[name="order-by"]')?.parent;
  while (form != null && form.localName != 'form') {
    form = form.parent;
  }
  if (form == null) return null;
  final filterForm = form;
  final genderValuePattern = RegExp(r'^[a-z][a-z0-9_]*$');
  final groups = <String, List<FaFilterOption>>{};
  for (final name in [
    SearchFilterGroups.orderBy,
    SearchFilterGroups.orderDirection,
    SearchFilterGroups.range,
    SearchFilterGroups.perPage,
  ]) {
    groups[name] = filterForm
        .querySelectorAll('select[name="$name"] option')
        .map((option) => FaFilterOption(
              field: name,
              value: option.attributes['value'] ?? '',
              label: option.text.trim(),
            ))
        .toList();
    if (groups[name]!.isEmpty) {
      groups[name] = _inputOptions(filterForm, 'input[name="$name"]');
    }
  }
  groups[SearchFilterGroups.mode] =
      _inputOptions(filterForm, 'input[name="mode"]');
  for (final group in [SearchFilterGroups.rating, SearchFilterGroups.type]) {
    groups[group] = _inputOptions(
      filterForm,
      'input[type="checkbox"][name^="$group-"]',
    );
  }
  var genderInputs = filterForm.querySelectorAll(
    '.js-filterSection__gender input[type="checkbox"]',
  );
  if (genderInputs.isEmpty) {
    genderInputs = filterForm
        .querySelectorAll('input[type="checkbox"]')
        .where((input) =>
            (input.attributes['name'] ?? '').isEmpty &&
            genderValuePattern.hasMatch(input.attributes['value'] ?? ''))
        .toList();
  }
  if (genderInputs.any((input) =>
      !genderValuePattern.hasMatch(input.attributes['value'] ?? ''))) {
    return null;
  }
  groups[SearchFilterGroups.gender] = genderInputs.map((input) {
    final value = input.attributes['value'] ?? '';
    return FaFilterOption(
      field: 'gender-$value',
      value: '1',
      label: _inputLabel(filterForm, input).replaceAll('_', ' '),
    );
  }).toList();
  final fieldNamePattern = RegExp(r'^[a-z][a-z0-9_-]*$');
  for (final options in groups.values) {
    if (options.isEmpty ||
        options.any((option) =>
            option.value.isEmpty ||
            option.label.isEmpty ||
            !fieldNamePattern.hasMatch(option.field)) ||
        options
                .map((option) => '${option.field}:${option.value}')
                .toSet()
                .length !=
            options.length) {
      return null;
    }
  }
  if (groups[SearchFilterGroups.perPage]!.any(
    (option) => FaPageSettings.positiveInteger(option.value) == null,
  )) {
    return null;
  }
  return FaFilterOptions(groups);
}

List<FaFilterOption> _inputOptions(Element form, String selector) {
  return form.querySelectorAll(selector).map((input) {
    return FaFilterOption(
      field: input.attributes['name'] ?? '',
      value: input.attributes['value'] ?? '',
      label: _inputLabel(form, input),
    );
  }).toList();
}

String _inputLabel(Element form, Element input) {
  var parent = input.parent;
  while (parent != null && parent != form) {
    if (parent.localName == 'label') {
      return parent.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    parent = parent.parent;
  }
  final id = input.attributes['id'];
  if (id == null || id.isEmpty) return '';
  for (final label in form.querySelectorAll('label[for]')) {
    if (label.attributes['for'] == id) {
      return label.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }
  return '';
}
