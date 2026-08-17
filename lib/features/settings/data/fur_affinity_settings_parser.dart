import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';

const String faAccountSettingsPath = '/controls/settings/';
const String faGlobalSiteSettingsPath = '/controls/site-settings/';
const String faUserSettingsPath = '/controls/user-settings/';
const String faPasswordResetPath = '/lostpw/';

FaSettingsFormSnapshot parseFaSettingsForm(
  String html, {
  required String expectedPath,
}) {
  final document = html_parser.parse(html);
  final form = _findForm(document, expectedPath);
  if (form == null) {
    final message = extractFaSettingsResponseMessage(html);
    throw FaSettingsRequestException(
      message ?? 'Fur Affinity did not return the expected settings form.',
    );
  }

  final action = form.attributes['action']?.trim() ?? expectedPath;
  final actionUri = Uri.parse('https://www.furaffinity.net').resolve(action);
  final pageUri = Uri.parse('https://www.furaffinity.net').resolve(expectedPath);
  final payload = <String, String>{};
  final fields = <String, FaFormFieldSnapshot>{};

  for (final input in form.querySelectorAll('input')) {
    final name = input.attributes['name']?.trim() ?? '';
    if (name.isEmpty) continue;
    final type = (input.attributes['type'] ?? 'text').toLowerCase();
    if (const <String>{
      'submit',
      'button',
      'reset',
      'file',
      'image',
    }.contains(type)) {
      continue;
    }

    final enabled = !input.attributes.containsKey('disabled');
    final value = input.attributes['value'] ?? '';
    final checked = input.attributes.containsKey('checked');

    if (type == 'radio') {
      final previous = fields[name];
      final options = <FaFormOption>[
        ...?previous?.options,
        FaFormOption(
          value: value,
          label: _inputLabel(form, input, value),
        ),
      ];
      fields[name] = FaFormFieldSnapshot(
        name: name,
        type: type,
        value: checked ? value : previous?.value ?? '',
        enabled: (previous?.enabled ?? false) || enabled,
        checked: (previous?.checked ?? false) || checked,
        options: options,
      );
      if (enabled && checked) payload[name] = value;
      continue;
    }

    fields[name] = FaFormFieldSnapshot(
      name: name,
      type: type,
      value: value,
      enabled: enabled,
      checked: checked,
      min: input.attributes['min'],
      max: input.attributes['max'],
    );
    if (!enabled) continue;
    if (type == 'checkbox') {
      if (checked) payload[name] = value.isEmpty ? 'on' : value;
    } else {
      payload[name] = value;
    }
  }

  for (final select in form.querySelectorAll('select')) {
    final name = select.attributes['name']?.trim() ?? '';
    if (name.isEmpty) continue;
    final enabled = !select.attributes.containsKey('disabled');
    final optionElements = select.querySelectorAll('option');
    final options = optionElements
        .map(
          (option) => FaFormOption(
            value: option.attributes['value'] ?? option.text.trim(),
            label: option.text.trim(),
          ),
        )
        .toList(growable: false);
    dom.Element? selected;
    for (final option in optionElements) {
      if (option.attributes.containsKey('selected')) {
        selected = option;
        break;
      }
    }
    if (selected == null && optionElements.isNotEmpty) {
      selected = optionElements.first;
    }
    final value = selected?.attributes['value'] ?? selected?.text.trim() ?? '';
    fields[name] = FaFormFieldSnapshot(
      name: name,
      type: 'select',
      value: value,
      enabled: enabled,
      checked: false,
      options: options,
    );
    if (enabled) payload[name] = value;
  }

  for (final textarea in form.querySelectorAll('textarea')) {
    final name = textarea.attributes['name']?.trim() ?? '';
    if (name.isEmpty) continue;
    final enabled = !textarea.attributes.containsKey('disabled');
    final value = textarea.text;
    fields[name] = FaFormFieldSnapshot(
      name: name,
      type: 'textarea',
      value: value,
      enabled: enabled,
      checked: false,
    );
    if (enabled) payload[name] = value;
  }

  return FaSettingsFormSnapshot(
    actionUri: actionUri,
    basePayload: payload,
    fields: fields,
    faPlusIconUri: _faPlusIconUri(document, pageUri),
  );
}

FaSettingsFormSnapshot? tryParseFaSettingsForm(
  String html, {
  required String expectedPath,
}) {
  try {
    return parseFaSettingsForm(html, expectedPath: expectedPath);
  } on FaSettingsRequestException {
    return null;
  }
}

String? extractFaSettingsResponseMessage(String html) {
  final systemMessage = parseFaSystemMessage(html);
  if (systemMessage != null) return systemMessage.message;

  final document = html_parser.parse(html);
  const selectors = <String>[
    '.error-message',
    '.alert-danger',
    '.validation-error',
    'section.notice-message',
    '.notice-message',
    '.redirect-message',
  ];
  for (final selector in selectors) {
    final text = document.querySelector(selector)?.text;
    final cleaned = _cleanMessage(text);
    if (cleaned != null) return cleaned;
  }

  final standardPage = document.querySelector('#standardpage');
  final heading = standardPage?.querySelector('h2')?.text.toLowerCase() ?? '';
  if (standardPage != null && heading.contains('system message')) {
    return _cleanMessage(standardPage.text);
  }
  return null;
}

bool isFaSettingsFailureMessage(String? message) {
  final lower = message?.toLowerCase().trim() ?? '';
  if (lower.isEmpty) return false;
  final strongFailure = const <String>[
    'error',
    'failed',
    'failure',
    'unsuccessful',
    'not successful',
    'incorrect',
    'invalid',
    'not correct',
    'not valid',
    'wrong password',
    'does not match',
    'do not match',
    'not match',
    'missing',
    'too short',
    'too long',
    'unable',
    'could not',
    'cannot',
    'denied',
    'forbidden',
    'unauthorized',
    'not authorized',
    'not permitted',
    'expired',
    'not found',
    'not updated',
    'not saved',
    'not changed',
    'not sent',
    'not reset',
    'maintenance',
    'unavailable',
    'try again',
    'too many requests',
    'rate limit',
    'remaining before',
    'second remaining',
    'seconds remaining',
    'please log in',
    'not logged in',
  ].any(lower.contains);
  if (strongFailure) return true;
  return lower.contains('required') && !_hasExplicitSuccessLanguage(lower);
}

bool isFaSettingsSuccessMessage(String? message) {
  final lower = message?.toLowerCase().trim() ?? '';
  if (lower.isEmpty || isFaSettingsFailureMessage(lower)) return false;
  return _hasExplicitSuccessLanguage(lower);
}

bool _hasExplicitSuccessLanguage(String lower) {
  if (const <String>[
    'success',
    'has been updated',
    'have been updated',
    'was updated',
    'were updated',
    'settings updated',
    'has been saved',
    'have been saved',
    'was saved',
    'were saved',
    'settings saved',
    'settings have been changed',
    'settings were changed',
    'settings changed',
    'changes applied',
    'change applied',
    'password has been reset',
    'password was reset',
    'password has been changed',
    'password was changed',
    'email has been sent',
    'email was sent',
    'email sent',
  ].any(lower.contains)) {
    return true;
  }
  if (lower.contains('code') &&
      const <String>['sent', 'emailed', 'mailed'].any(lower.contains)) {
    return true;
  }
  return lower.contains('check your email');
}

dom.Element? _findForm(dom.Document document, String expectedPath) {
  for (final form in document.querySelectorAll('form')) {
    final action = form.attributes['action']?.trim() ?? '';
    if (action.isEmpty) continue;
    final uri = Uri.parse('https://www.furaffinity.net').resolve(action);
    if (uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'www.furaffinity.net' ||
        uri.port != 443) {
      continue;
    }
    if (_normalizedPath(uri.path) != _normalizedPath(expectedPath)) continue;
    if (expectedPath == faPasswordResetPath) return form;
    final doValue = form
        .querySelector('input[name="do"]')
        ?.attributes['value']
        ?.toLowerCase();
    if (doValue == 'update') return form;
  }
  return null;
}

String _normalizedPath(String path) {
  if (path.endsWith('/')) return path;
  return '$path/';
}

Uri? _faPlusIconUri(dom.Document document, Uri pageUri) {
  final source =
      document.querySelector('img.fa-plus-icon')?.attributes['src']?.trim() ??
          '';
  if (source.isEmpty) return null;
  final uri = pageUri.resolve(source);
  if (uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) return null;
  return uri;
}

String _inputLabel(dom.Element form, dom.Element input, String fallback) {
  final id = input.attributes['id'];
  if (id != null && id.isNotEmpty) {
    for (final label in form.querySelectorAll('label')) {
      if (label.attributes['for'] == id) {
        final text = label.text.trim();
        if (text.isNotEmpty) return text;
      }
    }
  }
  final parent = input.parent;
  if (parent != null && parent.localName == 'label') {
    final text = parent.text.trim();
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

String? _cleanMessage(String? value) {
  final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  if (cleaned.isEmpty) return null;
  if (cleaned.length <= 240) return cleaned;
  return '${cleaned.substring(0, 237).trim()}...';
}
