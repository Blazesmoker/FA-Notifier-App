import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/settings/domain/fur_affinity_profile_management_models.dart';
import 'package:fanotifier/features/settings/domain/fur_affinity_settings_models.dart';

const String faProfileBannerPath = '/controls/profilebanner/';
const String faAvatarManagementPath = '/controls/avatar/';

FaProfileBannerSnapshot parseFaProfileBanner(String html) {
  final document = html_parser.parse(html);
  dom.Element? uploadForm;
  dom.Element? removeForm;
  for (final form in document.querySelectorAll('form')) {
    final uri = _tryStrictUri(form.attributes['action']);
    if (uri == null ||
        _normalized(uri.path) != _normalized(faProfileBannerPath)) {
      continue;
    }
    if (form.querySelector('[name="profile_banner"]') != null ||
        form.querySelector('[name="action-upload"]') != null) {
      uploadForm ??= form;
    }
    if (form.querySelector('[name="action-remove"]') != null) {
      removeForm ??= form;
    }
  }
  if (uploadForm == null) {
    throw const FaSettingsRequestException(
      'Fur Affinity did not return the expected profile banner form.',
    );
  }
  final payload = _formPayload(uploadForm);
  final submit = uploadForm.querySelector('[name="action-upload"]');
  if (submit != null) {
    payload['action-upload'] = submit.attributes['value'] ?? 'Upload';
  }
  final removePayload = removeForm == null
      ? <String, String>{}
      : _formPayload(removeForm);
  final removeSubmit = removeForm?.querySelector('[name="action-remove"]');
  if (removeSubmit != null) {
    removePayload['action-remove'] = removeSubmit.attributes['value'] ?? '';
  }
  return FaProfileBannerSnapshot(
    actionUri: _strictUri(
      uploadForm.attributes['action'] ?? faProfileBannerPath,
    ),
    payload: payload,
    currentBannerUri: _tryMediaUri(
      document
          .querySelector('.current-banner img.profile-banner-image')
          ?.attributes['src'],
    ),
    removeActionUri: removeForm == null
        ? null
        : _tryStrictUri(removeForm.attributes['action']),
    removePayload: removePayload,
  );
}

FaAvatarManagementSnapshot parseFaAvatarManagement(String html) {
  final document = html_parser.parse(html);
  final form = _strictForm(document, faAvatarManagementPath);
  if (form == null) {
    throw const FaSettingsRequestException(
      'Fur Affinity did not return the expected avatar management form.',
    );
  }
  final gallery = <FaAvatarGalleryItem>[];
  for (final anchor in document.querySelectorAll('a[href*="/avatar/chooseuseravatar/"]')) {
    final chooseUri = _tryStrictUri(anchor.attributes['href']);
    final imageUri = _tryMediaUri(anchor.querySelector('img')?.attributes['src']);
    if (chooseUri == null || imageUri == null) continue;
    final id = chooseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    Uri? removeUri;
    final container = anchor.parent;
    if (container != null) {
      final match = RegExp(r'''(/avatar/deleteavatar/[^\s'"]+/?)''')
          .firstMatch(container.outerHtml);
      removeUri = _tryStrictUri(match?.group(1));
    }
    gallery.add(
      FaAvatarGalleryItem(
        id: id,
        imageUri: imageUri,
        chooseUri: chooseUri,
        removeUri: removeUri,
      ),
    );
  }
  Uri? currentAvatarUri;
  for (final selector in const <String>[
    'img[alt="User Avatar"]',
    '#current-avatar img',
    '.current-avatar img',
    'img.current-avatar',
  ]) {
    currentAvatarUri = _tryMediaUri(document.querySelector(selector)?.attributes['src']);
    if (currentAvatarUri != null) break;
  }
  return FaAvatarManagementSnapshot(
    actionUri: _strictUri(form.attributes['action'] ?? faAvatarManagementPath),
    payload: _formPayload(form),
    currentAvatarUri: currentAvatarUri,
    gallery: gallery,
  );
}

dom.Element? _strictForm(dom.Document document, String expectedPath) {
  for (final form in document.querySelectorAll('form')) {
    final uri = _tryStrictUri(form.attributes['action']);
    if (uri != null && _normalized(uri.path) == _normalized(expectedPath)) {
      return form;
    }
  }
  return null;
}

Map<String, String> _formPayload(dom.Element form) {
  final payload = <String, String>{};
  for (final input in form.querySelectorAll('input')) {
    final name = input.attributes['name']?.trim() ?? '';
    final type = (input.attributes['type'] ?? 'text').toLowerCase();
    if (name.isEmpty || type == 'file' || type == 'submit') continue;
    if (type == 'checkbox' && !input.attributes.containsKey('checked')) continue;
    payload[name] = input.attributes['value'] ?? '';
  }
  return payload;
}

Uri _strictUri(String value) {
  final uri = _tryStrictUri(value);
  if (uri == null) {
    throw const FaSettingsRequestException('Fur Affinity returned an unsafe form action.');
  }
  return uri;
}

Uri? _tryStrictUri(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final uri = Uri.parse('https://www.furaffinity.net').resolve(raw);
  final host = uri.host.toLowerCase();
  if (uri.scheme.toLowerCase() != 'https' ||
      (host != 'www.furaffinity.net' && host != 'furaffinity.net') ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  return uri;
}

Uri? _tryMediaUri(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final uri = Uri.parse('https://www.furaffinity.net').resolve(raw);
  final host = uri.host.toLowerCase();
  if (uri.scheme.toLowerCase() != 'https' ||
      (host != 'furaffinity.net' && !host.endsWith('.furaffinity.net')) ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  return uri;
}

String _normalized(String path) => path.endsWith('/') ? path : '$path/';
