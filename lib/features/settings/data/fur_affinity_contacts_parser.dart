import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/settings/data/fur_affinity_settings_parser.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_contacts_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';

const String faContactsPath = '/controls/contacts/';

FaContactsFormSnapshot parseFaContactsForm(String html) {
  final formSnapshot = parseFaSettingsForm(
    html,
    expectedPath: faContactsPath,
  );
  final document = html_parser.parse(html);
  final form = _findContactsForm(document);
  if (form == null) {
    throw const FaSettingsRequestException(
      'Fur Affinity did not return the expected contacts form.',
    );
  }

  final pageUri = Uri.parse('https://www.furaffinity.net$faContactsPath');
  final sections = <FaContactSection>[];
  for (final section in form.querySelectorAll('section')) {
    final heading = section.querySelector('.section-header h2');
    final items = section.querySelectorAll('.control-panel-contact-item');
    if (heading == null || items.isEmpty) continue;

    final fields = <FaContactField>[];
    for (final item in items) {
      final input = item.querySelector('input[name]');
      if (input == null) continue;
      final name = input.attributes['name']?.trim() ?? '';
      final fieldSnapshot = formSnapshot.field(name);
      if (name.isEmpty || fieldSnapshot == null) continue;

      final label = item.querySelector('h4')?.text.trim() ?? name;
      final testUrl = item
          .querySelector('.contact-verify-url a')
          ?.attributes['data-test-url']
          ?.trim();
      fields.add(
        FaContactField(
          name: name,
          label: label.isEmpty ? name : label,
          placeholder: input.attributes['placeholder']?.trim() ?? '',
          inputType: (input.attributes['type'] ?? 'text').toLowerCase(),
          validationRules: _validationRules(
            input.attributes['data-requires'],
          ),
          maxLength: int.tryParse(input.attributes['maxlength'] ?? ''),
          min: int.tryParse(input.attributes['min'] ?? ''),
          max: int.tryParse(input.attributes['max'] ?? ''),
          verificationUrlTemplate:
              testUrl == null || testUrl.isEmpty ? null : testUrl,
          iconUri: _iconUri(item, pageUri),
        ),
      );
    }
    if (fields.isEmpty) continue;

    final rawTitle = heading.text.trim();
    final headerText = section.querySelector('.section-header')?.text ?? '';
    final description = headerText
        .replaceFirst(rawTitle, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    sections.add(
      FaContactSection(
        title: rawTitle.replaceFirst(RegExp(r'^Contact Info\s*-\s*'), ''),
        description: description.isEmpty ? null : description,
        fields: List<FaContactField>.unmodifiable(fields),
      ),
    );
  }

  if (sections.isEmpty) {
    throw const FaSettingsRequestException(
      'Fur Affinity did not return any contact fields.',
    );
  }
  return FaContactsFormSnapshot(
    form: formSnapshot,
    sections: List<FaContactSection>.unmodifiable(sections),
  );
}

dom.Element? _findContactsForm(dom.Document document) {
  for (final form in document.querySelectorAll('form')) {
    final action = form.attributes['action']?.trim() ?? '';
    if (action.isEmpty) continue;
    final uri = Uri.parse('https://www.furaffinity.net').resolve(action);
    if (uri.scheme == 'https' &&
        uri.host.toLowerCase() == 'www.furaffinity.net' &&
        uri.port == 443 &&
        _normalizedPath(uri.path) == faContactsPath) {
      return form;
    }
  }
  return null;
}

List<FaContactValidationRule> _validationRules(String? value) {
  final rules = <FaContactValidationRule>[];
  for (final name in value?.split(',') ?? const <String>[]) {
    switch (name.trim()) {
      case 'url':
        rules.add(FaContactValidationRule.url);
        break;
      case 'username':
        rules.add(FaContactValidationRule.username);
        break;
      case 'user_id':
        rules.add(FaContactValidationRule.userId);
        break;
      case 'stoat_username':
        rules.add(FaContactValidationRule.stoatUsername);
        break;
    }
  }
  return List<FaContactValidationRule>.unmodifiable(rules);
}

Uri? _iconUri(dom.Element item, Uri pageUri) {
  final source = item.querySelector('picture source')?.attributes['srcset'];
  final image = item.querySelector('picture img')?.attributes['src'];
  final sourceParts = (source?.split(RegExp(r'[\s,]')) ?? const <String>[])
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  final raw = (sourceParts.isEmpty ? image ?? '' : sourceParts.first).trim();
  if (raw.isEmpty) return null;
  final uri = pageUri.resolve(raw);
  final host = uri.host.toLowerCase();
  if (uri.scheme != 'https' ||
      (host != 'furaffinity.net' && !host.endsWith('.furaffinity.net'))) {
    return null;
  }
  return uri;
}

String _normalizedPath(String path) {
  return path.endsWith('/') ? path : '$path/';
}
