import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/shared/fa/fa_system_message_parser.dart';

const String faSubmissionManagementPath = '/controls/submissions/';
const String faFolderManagementPath = '/controls/folders/submissions/';
const String faFolderAddPath =
    '/controls/folders/submissions/folder/add/';
const String faFolderEditPath =
    '/controls/folders/submissions/folder/edit/';

FaSubmissionManagementPage parseSubmissionManagementPage(
  String html, {
  required Uri sourceUri,
}) {
  final document = html_parser.parse(html);
  final form = document.querySelector('form[name="replyform"]') ??
      _findFormByPath(document, faSubmissionManagementPath);
  if (form == null) {
    throw SubmissionManagementRequestException(
      _responseMessage(document, html) ??
          'Fur Affinity did not return the submissions management form.',
    );
  }

  final baseFields = _successfulFormValues(form);
  final actions = <SubmissionManagementActionType, FaManagementFormAction>{};
  const buttonNames = <SubmissionManagementActionType, String>{
    SubmissionManagementActionType.assignToFolder: 'assign_folder_submit',
    SubmissionManagementActionType.createFolder: 'create_folder_submit',
    SubmissionManagementActionType.unassignFromFolders:
        'remove_from_folders_submit',
    SubmissionManagementActionType.moveToScraps: 'move_to_scraps_submit',
    SubmissionManagementActionType.moveToGallery: 'move_from_scraps_submit',
    SubmissionManagementActionType.deleteSubmissions:
        'delete_submissions_submit',
  };
  for (final entry in buttonNames.entries) {
    final button = form.querySelector('[name="${entry.value}"]');
    if (button == null) continue;
    actions[entry.key] = _formAction(
      form,
      sourceUri,
      fields: baseFields,
      button: button,
    );
  }

  final folders = <FaSubmissionFolderOption>[];
  String? selectedFolderId;
  final folderSelect = form.querySelector('select[name="assign_folder_id"]');
  if (folderSelect != null) {
    for (final option in folderSelect.querySelectorAll('option')) {
      final id = option.attributes['value']?.trim() ?? '';
      if (id.isEmpty || id == '0') continue;
      if (option.attributes.containsKey('selected')) selectedFolderId = id;
      final parent = option.parent;
      final groupLabel = parent?.localName == 'optgroup'
          ? _cleanText(parent?.attributes['label'])
          : null;
      folders.add(
        FaSubmissionFolderOption(
          id: id,
          label: _cleanText(option.text) ?? id,
          groupLabel: groupLabel,
        ),
      );
    }
  }

  final descriptionData = _submissionDescriptions(document);
  final submissions = <FaManagedSubmission>[];
  for (final figure in
      form.querySelectorAll('#gallery-manage-submissions figure')) {
    final checkbox = figure.querySelector('input[name="submission_ids[]"]');
    final id = checkbox?.attributes['value']?.trim() ?? '';
    final postAnchor = figure.querySelector('a[href*="/view/"]');
    final image = figure.querySelector('img[src]');
    final postHref = postAnchor?.attributes['href']?.trim() ?? '';
    final imageSource = image?.attributes['src']?.trim() ?? '';
    if (id.isEmpty || postHref.isEmpty || imageSource.isEmpty) continue;
    final captionAnchor = figure.querySelector('figcaption a[href*="/view/"]');
    final title = _cleanText(captionAnchor?.text) ??
        _cleanText(captionAnchor?.attributes['title']) ??
        id;
    final classes = figure.classes;
    final rating = classes.contains('r-adult')
        ? 'adult'
        : classes.contains('r-mature')
            ? 'mature'
            : classes.contains('r-general')
                ? 'general'
                : null;
    final width = _positiveDouble(image?.attributes['data-width']) ?? 1;
    final height = _positiveDouble(image?.attributes['data-height']) ?? 1;
    final missingTags = figure.querySelectorAll('[title]').any((element) {
      return (element.attributes['title'] ?? '')
          .toLowerCase()
          .contains('missing tags');
    });
    submissions.add(
      FaManagedSubmission(
        id: id,
        title: title,
        thumbnailUri: _resolveUri(sourceUri, imageSource),
        postUri: _resolveUri(sourceUri, postHref),
        rating: rating,
        width: width,
        height: height,
        missingTags: missingTags,
        assignedFolders: _assignedFolders(descriptionData[id]),
      ),
    );
  }

  Uri? newerUri = _paginationUri(form, sourceUri, 'Newer');
  Uri? olderUri = _paginationUri(form, sourceUri, 'Older');
  if (_sameLocation(newerUri, sourceUri)) newerUri = null;
  if (_sameLocation(olderUri, sourceUri)) olderUri = null;

  return FaSubmissionManagementPage(
    sourceUri: sourceUri,
    folders: folders,
    submissions: submissions,
    actions: actions,
    selectedFolderId: selectedFolderId,
    newerUri: newerUri,
    olderUri: olderUri,
    mainGalleryUri: _mainGalleryUri(descriptionData, sourceUri),
    currentPage: _paginationPageNumber(sourceUri, newerUri, olderUri),
  );
}

FaFolderManagementPage parseFolderManagementPage(
  String html, {
  required Uri sourceUri,
}) {
  final document = html_parser.parse(html);
  final root = document.querySelector('#page-controls-folders-submissions');
  if (root == null) {
    throw SubmissionManagementRequestException(
      _responseMessage(document, html) ??
          'Fur Affinity did not return the folder management page.',
    );
  }

  final createGroupForm = root.querySelector('form#add-group');
  final renameGroupForm = root.querySelector('form#edit-group');
  final groups = <FaManagedFolderGroup>[];
  for (final row in root.querySelectorAll('tr.group-row')) {
    final id = _classNumber(row, 'group-') ??
        row.querySelector('input[name="group_id"]')?.attributes['value'];
    if (id == null || id.isEmpty) continue;
    final name = (_cleanText(row.querySelector('h2')?.text) ?? id)
        .replaceFirst(RegExp(r'\s*\(Group\)\s*$'), '')
        .trim();
    groups.add(
      FaManagedFolderGroup(
        id: id,
        name: name,
        moveUpAction: _rowAction(
          row,
          sourceUri,
          pathFragment: '/group/move-to/',
          direction: 'up',
        ),
        moveDownAction: _rowAction(
          row,
          sourceUri,
          pathFragment: '/group/move-to/',
          direction: 'down',
        ),
        deleteAction: _rowAction(
          row,
          sourceUri,
          pathFragment: '/group/delete/',
        ),
        addFolderAction: _rowAction(
          row,
          sourceUri,
          pathFragment: '/folder/add/',
        ),
      ),
    );
  }

  final folders = <FaManagedFolder>[];
  for (final row in root.querySelectorAll('tr.folder-row')) {
    final id = _classNumber(row, 'folder-') ??
        row.querySelector('input[name="folder_id"]')?.attributes['value'];
    if (id == null || id.isEmpty) continue;
    final groupId = _classNumber(row, 'group-') ?? '0';
    final nameCell = row.querySelector('.name-desc');
    final name = (_cleanText(row.querySelector('.folder-name h3')?.text) ?? id)
        .replaceFirst(RegExp(r'\s*\(Folder\)\s*$'), '')
        .trim();
    final countMatch = RegExp(r'(\d+)\s+Submissions?', caseSensitive: false)
        .firstMatch(nameCell?.text ?? '');
    var description = _cleanText(nameCell?.text);
    if (description != null) {
      description = description.replaceFirst('$name (Folder)', '');
      final countText = countMatch?.group(0);
      if (countText != null) {
        description = description.replaceFirst(countText, '');
      }
      description = description.trim();
      if (description.isEmpty) description = null;
    }
    final galleryHref =
        row.querySelector('a.folder-name')?.attributes['href']?.trim();
    final iconSource = row.querySelector('img[src]')?.attributes['src']?.trim();
    folders.add(
      FaManagedFolder(
        id: id,
        name: name,
        submissionCount: int.tryParse(countMatch?.group(1) ?? '') ?? 0,
        groupId: groupId,
        description: description,
        galleryUri: galleryHref == null || galleryHref.isEmpty
            ? null
            : _resolveUri(sourceUri, galleryHref),
        iconUri: iconSource == null || iconSource.isEmpty
            ? null
            : _resolveUri(sourceUri, iconSource),
        moveUpAction: _rowAction(
          row,
          sourceUri,
          pathFragment: '/folder/move-to/',
          direction: 'up',
        ),
        moveDownAction: _rowAction(
          row,
          sourceUri,
          pathFragment: '/folder/move-to/',
          direction: 'down',
        ),
        editAction: _rowAction(
          row,
          sourceUri,
          pathFragment: '/folder/edit/',
        ),
        deleteAction: _rowAction(
          row,
          sourceUri,
          pathFragment: '/folder/delete/',
        ),
        addSubmissionsAction: _rowAction(
          row,
          sourceUri,
          exactPath: faSubmissionManagementPath,
        ),
      ),
    );
  }

  final pageText = root.text.replaceAll(RegExp(r'\s+'), ' ');
  final maximumFolders = RegExp(
    r'Maximum Folders Allowed:\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(pageText);
  final maximumGroups = RegExp(
    r'Maximum Groups Allowed:\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(pageText);
  final faPlusHref = root
      .querySelector('a[href*="/plus/"]')
      ?.attributes['href']
      ?.trim();
  final faPlusIconSource = root
      .querySelector('img.fa-plus-icon')
      ?.attributes['src']
      ?.trim();
  final createFolderHref = root
      .querySelector('a.add-folder[href]')
      ?.attributes['href']
      ?.trim();

  return FaFolderManagementPage(
    sourceUri: sourceUri,
    maximumFolders: int.tryParse(maximumFolders?.group(1) ?? ''),
    maximumGroups: int.tryParse(maximumGroups?.group(1) ?? ''),
    groups: groups,
    folders: folders,
    faPlusUri: faPlusHref == null || faPlusHref.isEmpty
        ? null
        : _resolveUri(sourceUri, faPlusHref),
    faPlusIconUri: faPlusIconSource == null || faPlusIconSource.isEmpty
        ? null
        : _resolveUri(sourceUri, faPlusIconSource),
    createFolderUri: createFolderHref == null || createFolderHref.isEmpty
        ? null
        : _resolveUri(sourceUri, createFolderHref),
    createGroupAction: createGroupForm == null
        ? null
        : _formAction(
            createGroupForm,
            sourceUri,
            fields: _successfulFormValues(createGroupForm),
            button: createGroupForm.querySelector('[type="submit"]'),
          ),
    renameGroupAction: renameGroupForm == null
        ? null
        : _formAction(
            renameGroupForm,
            sourceUri,
            fields: _successfulFormValues(renameGroupForm),
            button: renameGroupForm.querySelector('[type="submit"]'),
          ),
  );
}

FaFolderEditorPage parseFolderEditorPage(
  String html, {
  required Uri sourceUri,
}) {
  final document = html_parser.parse(html);
  final form = _findFolderEditorForm(document);
  if (form == null) {
    throw SubmissionManagementRequestException(
      _responseMessage(document, html) ??
          'Fur Affinity did not return the folder editor form.',
    );
  }

  final hiddenFields = <FaManagementFormValue>[];
  for (final input in form.querySelectorAll('input')) {
    final name = input.attributes['name']?.trim() ?? '';
    final type = (input.attributes['type'] ?? 'text').toLowerCase();
    if (name.isEmpty || type != 'hidden') continue;
    hiddenFields.add(
      FaManagementFormValue(name, input.attributes['value'] ?? ''),
    );
  }
  final submit = form.querySelector('button[type="submit"]') ??
      form.querySelector('input[type="submit"]');
  final groupSelect = form.querySelector('select[name="group_id"]');
  final createGroupInput =
      form.querySelector('input[name="create_group_name"]');
  final folderNameInput = form.querySelector('input[name="folder_name"]');
  final folderDescription =
      form.querySelector('textarea[name="folder_description"]');
  final submitName = submit?.attributes['name']?.trim();
  final submitValue = submit?.attributes['value']?.trim();
  if (submit == null ||
      groupSelect == null ||
      createGroupInput == null ||
      folderNameInput == null ||
      folderDescription == null ||
      submitName != 'key' ||
      submitValue == null ||
      submitValue.isEmpty) {
    throw const SubmissionManagementRequestException(
      'Fur Affinity returned an unexpected folder editor form.',
    );
  }

  final groupOptions = groupSelect.querySelectorAll('option');
  if (groupOptions.isEmpty) {
    throw const SubmissionManagementRequestException(
      'Fur Affinity returned an unexpected folder group list.',
    );
  }
  final selectedGroup = groupOptions.firstWhere(
    (option) => option.attributes.containsKey('selected'),
    orElse: () => groupOptions.first,
  );
  final fields = <FaFolderEditorField>[
    FaFolderEditorField(
      name: 'group_id',
      label: 'Assign to an existing group',
      type: FaFolderEditorFieldType.select,
      selectedValues: <String>[
        selectedGroup.attributes['value'] ?? selectedGroup.text.trim(),
      ],
      options: <FaFolderEditorOption>[
        for (final option in groupOptions)
          FaFolderEditorOption(
            value: option.attributes['value'] ?? option.text.trim(),
            label: _cleanText(option.text) ?? '',
          ),
      ],
    ),
    FaFolderEditorField(
      name: 'create_group_name',
      label: 'Or create new group named',
      type: FaFolderEditorFieldType.text,
      selectedValues: <String>[
        createGroupInput.attributes['value'] ?? '',
      ],
      options: const <FaFolderEditorOption>[],
    ),
    FaFolderEditorField(
      name: 'folder_name',
      label: 'Folder Name',
      type: FaFolderEditorFieldType.text,
      selectedValues: <String>[folderNameInput.attributes['value'] ?? ''],
      options: const <FaFolderEditorOption>[],
      requiredField: true,
      maxLength: int.tryParse(folderNameInput.attributes['maxlength'] ?? '') ?? 64,
    ),
    FaFolderEditorField(
      name: 'folder_description',
      label: 'Folder Description',
      type: FaFolderEditorFieldType.multiline,
      selectedValues: <String>[folderDescription.text],
      options: const <FaFolderEditorOption>[],
    ),
  ];

  final title = _editorTitle(document, form);
  final supportingTexts = <String>[];
  dom.Element? scope = form.parent;
  for (var i = 0; i < 3 && scope != null; i++) {
    final texts = scope.querySelectorAll('p, .section-warning');
    for (final element in texts) {
      final text = _cleanText(element.text);
      if (text != null && !supportingTexts.contains(text)) {
        supportingTexts.add(text);
      }
    }
    if (supportingTexts.isNotEmpty) break;
    scope = scope.parent;
  }

  return FaFolderEditorPage(
    sourceUri: sourceUri,
    title: title,
    submitLabel: _cleanText(submit.text) ??
        (_normalizePath(sourceUri.path) == faFolderEditPath
            ? 'Update'
            : 'Create'),
    isEditing: _normalizePath(sourceUri.path) == faFolderEditPath,
    action: _formAction(
      form,
      sourceUri,
      fields: hiddenFields,
      button: submit,
    ),
    fields: fields,
    supportingTexts: supportingTexts,
  );
}

String? extractSubmissionManagementResponseMessage(String html) {
  final systemMessage = parseFaSystemMessage(html);
  if (systemMessage != null) return systemMessage.message;
  final document = html_parser.parse(html);
  return _responseMessage(document, html);
}

dom.Element? _findFormByPath(dom.Document document, String expectedPath) {
  for (final form in document.querySelectorAll('form')) {
    final action = form.attributes['action']?.trim() ?? '';
    if (action.isEmpty) continue;
    final uri = _resolveUri(Uri.parse('https://www.furaffinity.net/'), action);
    if (_normalizePath(uri.path) == _normalizePath(expectedPath)) return form;
  }
  return null;
}

dom.Element? _findFolderEditorForm(dom.Document document) {
  for (final form in document.querySelectorAll('form')) {
    final method = (form.attributes['method'] ?? 'get').toLowerCase();
    final action = form.attributes['action']?.trim() ?? '';
    if (method != 'post' || action.isEmpty) continue;
    final uri = _resolveUri(Uri.parse('https://www.furaffinity.net/'), action);
    final path = _normalizePath(uri.path);
    if (path != faFolderAddPath && path != faFolderEditPath) continue;
    final hasEditable = form.querySelectorAll('input, select, textarea').any(
      (element) {
        if (element.localName != 'input') return true;
        final type = (element.attributes['type'] ?? 'text').toLowerCase();
        return !const <String>{'hidden', 'submit', 'button'}.contains(type);
      },
    );
    if (hasEditable) return form;
  }
  return null;
}

List<FaManagementFormValue> _successfulFormValues(dom.Element form) {
  final fields = <FaManagementFormValue>[];
  for (final input in form.querySelectorAll('input')) {
    final name = input.attributes['name']?.trim() ?? '';
    if (name.isEmpty || input.attributes.containsKey('disabled')) continue;
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
    if ((type == 'checkbox' || type == 'radio') &&
        !input.attributes.containsKey('checked')) {
      continue;
    }
    if (name == 'submission_ids[]') continue;
    fields.add(FaManagementFormValue(name, input.attributes['value'] ?? ''));
  }
  for (final select in form.querySelectorAll('select')) {
    final name = select.attributes['name']?.trim() ?? '';
    if (name.isEmpty || select.attributes.containsKey('disabled')) continue;
    final options = select.querySelectorAll('option');
    dom.Element? selected;
    for (final option in options) {
      if (option.attributes.containsKey('selected')) {
        selected = option;
        break;
      }
    }
    selected ??= options.isEmpty ? null : options.first;
    if (selected != null) {
      fields.add(
        FaManagementFormValue(
          name,
          selected.attributes['value'] ?? selected.text.trim(),
        ),
      );
    }
  }
  for (final textarea in form.querySelectorAll('textarea')) {
    final name = textarea.attributes['name']?.trim() ?? '';
    if (name.isEmpty || textarea.attributes.containsKey('disabled')) continue;
    fields.add(FaManagementFormValue(name, textarea.text));
  }
  return fields;
}

FaManagementFormAction _formAction(
  dom.Element form,
  Uri sourceUri, {
  required Iterable<FaManagementFormValue> fields,
  dom.Element? button,
}) {
  final action = form.attributes['action']?.trim();
  final submitName = button?.attributes['name']?.trim();
  return FaManagementFormAction(
    uri: _resolveUri(sourceUri, action == null || action.isEmpty ? sourceUri.toString() : action),
    fields: fields,
    submitName: submitName == null || submitName.isEmpty ? null : submitName,
    submitValue: submitName == null || submitName.isEmpty
        ? null
        : button?.attributes['value'] ?? button?.text.trim() ?? '',
  );
}

FaManagementFormAction? _rowAction(
  dom.Element row,
  Uri sourceUri, {
  String? pathFragment,
  String? exactPath,
  String? direction,
}) {
  for (final form in row.querySelectorAll('form')) {
    final action = form.attributes['action']?.trim() ?? '';
    if (action.isEmpty) continue;
    final uri = _resolveUri(sourceUri, action);
    final path = _normalizePath(uri.path);
    if (exactPath != null && path != _normalizePath(exactPath)) continue;
    if (pathFragment != null && !path.contains(pathFragment)) continue;
    if (direction != null) {
      final value = form
          .querySelector('input[name="direction"]')
          ?.attributes['value'];
      if (value != direction) continue;
    }
    return _formAction(
      form,
      sourceUri,
      fields: _successfulFormValues(form),
      button: form.querySelector('[type="submit"]'),
    );
  }
  return null;
}

Map<String, dynamic> _submissionDescriptions(dom.Document document) {
  final raw = document.querySelector('script#js-submissionData')?.text.trim();
  if (raw == null || raw.isEmpty) return const <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  } catch (_) {
    return const <String, dynamic>{};
  }
}

Uri? _mainGalleryUri(Map<String, dynamic> descriptions, Uri sourceUri) {
  for (final data in descriptions.values) {
    if (data is! Map) continue;
    final username = data['lower'];
    if (username is! String || username.trim().isEmpty) continue;
    return _resolveUri(
      sourceUri,
      '/gallery/${Uri.encodeComponent(username.trim())}/',
    );
  }
  return null;
}

List<String> _assignedFolders(dynamic data) {
  if (data is! Map) return const <String>[];
  final description = data['description'];
  if (description is! String || description.isEmpty) return const <String>[];
  const marker = 'This submission is assigned to the following folders:';
  final markerIndex = description.indexOf(marker);
  if (markerIndex < 0) return const <String>[];
  final fragment = description.substring(markerIndex + marker.length);
  final text = html_parser.parseFragment(fragment).text ?? '';
  final folders = <String>[];
  for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
    var line = rawLine.trim();
    if (line.startsWith('*')) line = line.substring(1).trim();
    line = line.replaceFirst(RegExp(r'^[—–-]+\s*(?:--)?\s*'), '').trim();
    if (line.isNotEmpty && !folders.contains(line)) folders.add(line);
  }
  return folders;
}

Uri? _paginationUri(dom.Element form, Uri sourceUri, String label) {
  for (final anchor in form.querySelectorAll('a[href]')) {
    if (_cleanText(anchor.text)?.toLowerCase() == label.toLowerCase()) {
      return _resolveUri(sourceUri, anchor.attributes['href']!);
    }
  }
  return null;
}

int _paginationPageNumber(Uri sourceUri, Uri? newerUri, Uri? olderUri) {
  final sourcePage = _pageNumberFromUri(sourceUri);
  if (sourcePage != null) return sourcePage;
  final newerPage = newerUri == null ? null : _pageNumberFromUri(newerUri);
  if (newerPage != null) return newerPage + 1;
  final olderPage = olderUri == null ? null : _pageNumberFromUri(olderUri);
  if (olderPage != null && olderPage > 1) return olderPage - 1;
  return 1;
}

int? _pageNumberFromUri(Uri uri) {
  for (final key in const <String>['page', 'p']) {
    final value = int.tryParse(uri.queryParameters[key] ?? '');
    if (value != null && value >= 0) return value + 1;
  }
  for (final segment in uri.pathSegments.reversed) {
    final value = int.tryParse(segment);
    if (value != null && value >= 0) return value + 1;
  }
  return null;
}

String? _classNumber(dom.Element element, String prefix) {
  for (final className in element.classes) {
    if (!className.startsWith(prefix)) continue;
    final value = className.substring(prefix.length);
    if (RegExp(r'^\d+$').hasMatch(value)) return value;
  }
  return null;
}

String _editorTitle(dom.Document document, dom.Element form) {
  dom.Element? parent = form.parent;
  for (var i = 0; i < 5 && parent != null; i++) {
    final heading = parent.querySelector('.section-header h2, h2');
    final text = _cleanText(heading?.text);
    if (text != null && !text.toLowerCase().contains('system message')) {
      return text;
    }
    parent = parent.parent;
  }
  return _cleanText(document.querySelector('#site-content h2')?.text) ??
      'Folder';
}

String? _responseMessage(dom.Document document, String html) {
  final systemMessage = parseFaSystemMessage(html);
  if (systemMessage != null) return systemMessage.message;
  const selectors = <String>[
    '.error-message',
    '.alert-danger',
    '.validation-error',
    '.notice-message',
    '.redirect-message',
  ];
  for (final selector in selectors) {
    final text = _cleanText(document.querySelector(selector)?.text);
    if (text != null) return text;
  }
  return null;
}

String _normalizePath(String path) {
  return path.endsWith('/') ? path : '$path/';
}

Uri _resolveUri(Uri base, String raw) {
  final value = raw.trim();
  if (value.startsWith('//')) return Uri.parse('${base.scheme}:$value');
  return base.resolve(value);
}

bool _sameLocation(Uri? left, Uri right) {
  if (left == null) return false;
  return left.scheme == right.scheme &&
      left.host == right.host &&
      left.path == right.path &&
      left.query == right.query;
}

double? _positiveDouble(String? value) {
  final parsed = double.tryParse(value ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

String? _cleanText(String? value) {
  final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  return cleaned.isEmpty ? null : cleaned;
}
