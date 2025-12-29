// lib/screens/submission_template_store.dart

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SubmissionTemplateStore {
  static const int version = 1;
  static const String _prefsKey = 'fa_submission_templates_v1';

  Future<List<SubmissionTemplate>> loadTemplates() async {
    final payload = await _loadPayload();
    final templates = payload.templates;

    if (templates.isEmpty) return [];

    final byId = <String, SubmissionTemplate>{
      for (final t in templates) t.id: t,
    };

    final ordered = <SubmissionTemplate>[];
    final seen = <String>{};

    for (final id in payload.order) {
      final t = byId[id];
      if (t != null && !seen.contains(id)) {
        ordered.add(t);
        seen.add(id);
      }
    }

    final leftovers = templates.where((t) => !seen.contains(t.id)).toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    ordered.addAll(leftovers);

    return ordered;
  }

  Future<void> upsertTemplate(SubmissionTemplate template) async {
    final payload = await _loadPayload();
    final templates = payload.templates;
    final order = payload.order;

    final idx = templates.indexWhere((t) => t.id == template.id);
    if (idx >= 0) {
      templates[idx] = template;
      if (!order.contains(template.id)) {
        order.insert(0, template.id);
      }
    } else {
      templates.add(template);
      order.remove(template.id);
      order.insert(0, template.id);
    }

    await _saveAll(templates, order);
  }

  Future<void> deleteTemplate(String id) async {
    final payload = await _loadPayload();
    payload.templates.removeWhere((t) => t.id == id);
    payload.order.removeWhere((x) => x == id);
    await _saveAll(payload.templates, payload.order);
  }

  Future<void> renameTemplate(String id, String newName) async {
    final payload = await _loadPayload();
    final idx = payload.templates.indexWhere((t) => t.id == id);
    if (idx < 0) return;

    final old = payload.templates[idx];
    payload.templates[idx] = old.copyWith(
      name: newName,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    if (!payload.order.contains(id)) {
      payload.order.insert(0, id);
    }

    await _saveAll(payload.templates, payload.order);
  }

  Future<void> saveOrder(List<String> orderedIds) async {
    final payload = await _loadPayload();
    final existingIds = payload.templates.map((e) => e.id).toSet();

    final cleaned = <String>[];
    for (final id in orderedIds) {
      if (existingIds.contains(id) && !cleaned.contains(id)) {
        cleaned.add(id);
      }
    }
    for (final id in existingIds) {
      if (!cleaned.contains(id)) cleaned.add(id);
    }

    await _saveAll(payload.templates, cleaned);
  }

  Future<_TemplatesPayload> _loadPayload() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const _TemplatesPayload(templates: [], order: []);
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const _TemplatesPayload(templates: [], order: []);
      }

      final v = decoded['version'];
      if (v is int && v != version) {
        return const _TemplatesPayload(templates: [], order: []);
      }

      final list = decoded['templates'];
      if (list is! List) {
        return const _TemplatesPayload(templates: [], order: []);
      }

      final templates = <SubmissionTemplate>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final t = SubmissionTemplate.fromJson(item);
          if (t.id.trim().isNotEmpty) templates.add(t);
        }
      }

      final orderRaw = decoded['order'];
      final order = <String>[];
      if (orderRaw is List) {
        for (final x in orderRaw) {
          if (x is String && x.trim().isNotEmpty) order.add(x);
        }
      }

      return _TemplatesPayload(templates: templates, order: order);
    } catch (_) {
      return const _TemplatesPayload(templates: [], order: []);
    }
  }

  Future<void> _saveAll(List<SubmissionTemplate> templates, List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'version': version,
      'templates': templates.map((e) => e.toJson()).toList(),
      'order': order,
    };
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}

class _TemplatesPayload {
  final List<SubmissionTemplate> templates;
  final List<String> order;

  const _TemplatesPayload({required this.templates, required this.order});
}

class TemplateSelectValue {
  final String value;
  final String label;

  const TemplateSelectValue({required this.value, required this.label});

  Map<String, dynamic> toJson() => {'value': value, 'label': label};

  static TemplateSelectValue? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final v = json['value'];
    final l = json['label'];
    if (v is! String || l is! String) return null;
    return TemplateSelectValue(value: v, label: l);
  }
}

class SubmissionTemplateFields {
  final TemplateSelectValue? category;
  final TemplateSelectValue? theme;
  final TemplateSelectValue? species;
  final TemplateSelectValue? rating;
  final String? title;
  final String? description;
  final String? keywords;

  final String? folderName;
  final List<TemplateSelectValue>? folders;

  const SubmissionTemplateFields({
    this.category,
    this.theme,
    this.species,
    this.rating,
    this.title,
    this.description,
    this.keywords,
    this.folderName,
    this.folders,
  });

  Map<String, dynamic> toJson() => {
    'category': category?.toJson(),
    'theme': theme?.toJson(),
    'species': species?.toJson(),
    'rating': rating?.toJson(),
    'title': title,
    'description': description,
    'keywords': keywords,
    'folderName': folderName,
    'folders': folders?.map((e) => e.toJson()).toList(),
  };

  static SubmissionTemplateFields fromJson(Map<String, dynamic> json) {
    List<TemplateSelectValue>? folders;
    final foldersRaw = json['folders'];
    if (foldersRaw is List) {
      final out = <TemplateSelectValue>[];
      for (final x in foldersRaw) {
        final v = TemplateSelectValue.fromJson(x);
        if (v != null) out.add(v);
      }
      folders = out.isEmpty ? null : out;
    }

    return SubmissionTemplateFields(
      category: TemplateSelectValue.fromJson(json['category']),
      theme: TemplateSelectValue.fromJson(json['theme']),
      species: TemplateSelectValue.fromJson(json['species']),
      rating: TemplateSelectValue.fromJson(json['rating']),
      title: json['title'] is String ? json['title'] as String : null,
      description: json['description'] is String ? json['description'] as String : null,
      keywords: json['keywords'] is String ? json['keywords'] as String : null,
      folderName: json['folderName'] is String ? json['folderName'] as String : null,
      folders: folders,
    );
  }
}

class SubmissionTemplate {
  final String id;
  final String name;
  final int updatedAtMs;
  final SubmissionTemplateFields fields;

  const SubmissionTemplate({
    required this.id,
    required this.name,
    required this.updatedAtMs,
    required this.fields,
  });

  SubmissionTemplate copyWith({
    String? id,
    String? name,
    int? updatedAtMs,
    SubmissionTemplateFields? fields,
  }) {
    return SubmissionTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      fields: fields ?? this.fields,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAtMs': updatedAtMs,
    'fields': fields.toJson(),
  };

  static SubmissionTemplate fromJson(Map<String, dynamic> json) {
    final id = (json['id'] is String) ? json['id'] as String : '';
    final name = (json['name'] is String) ? json['name'] as String : '';
    final updatedAtMs = (json['updatedAtMs'] is int) ? json['updatedAtMs'] as int : 0;
    final fieldsJson = (json['fields'] is Map<String, dynamic>)
        ? (json['fields'] as Map<String, dynamic>)
        : <String, dynamic>{};

    return SubmissionTemplate(
      id: id,
      name: name,
      updatedAtMs: updatedAtMs,
      fields: SubmissionTemplateFields.fromJson(fieldsJson),
    );
  }
}
