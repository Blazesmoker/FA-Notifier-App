import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanotifier/features/upload/domain/submission_template.dart';

class SubmissionTemplateStore {
  static const int version = 1;
  static const String _prefsKey = 'fa_submission_templates_v1';

  Future<List<SubmissionTemplate>> loadTemplates() async {
    final payload = await _loadPayload();
    final templates = payload.templates;

    if (templates.isEmpty) return [];

    final byId = <String, SubmissionTemplate>{
      for (final storedTemplate in templates) storedTemplate.id: storedTemplate,
    };

    final ordered = <SubmissionTemplate>[];
    final seen = <String>{};

    for (final id in payload.order) {
      final storedTemplate = byId[id];
      if (storedTemplate != null && !seen.contains(id)) {
        ordered.add(storedTemplate);
        seen.add(id);
      }
    }

    final leftovers = templates
        .where((storedTemplate) => !seen.contains(storedTemplate.id))
        .toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    ordered.addAll(leftovers);

    return ordered;
  }

  Future<void> upsertTemplate(SubmissionTemplate template) async {
    final payload = await _loadPayload();
    final templates = payload.templates;
    final order = payload.order;

    final templateIndex = templates.indexWhere(
      (storedTemplate) => storedTemplate.id == template.id,
    );
    if (templateIndex >= 0) {
      templates[templateIndex] = template;
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
    payload.templates.removeWhere((storedTemplate) => storedTemplate.id == id);
    payload.order.removeWhere((templateId) => templateId == id);
    await _saveAll(payload.templates, payload.order);
  }

  Future<void> renameTemplate(String id, String newName) async {
    final payload = await _loadPayload();
    final templateIndex = payload.templates.indexWhere(
      (storedTemplate) => storedTemplate.id == id,
    );
    if (templateIndex < 0) return;

    final old = payload.templates[templateIndex];
    payload.templates[templateIndex] = old.copyWith(
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
      return _TemplatesPayload(templates: <SubmissionTemplate>[], order: <String>[]);
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return _TemplatesPayload(templates: <SubmissionTemplate>[], order: <String>[]);
      }

      final storedVersion = decoded['version'];
      if (storedVersion is int && storedVersion != version) {
        return _TemplatesPayload(templates: <SubmissionTemplate>[], order: <String>[]);
      }

      final rawTemplates = decoded['templates'];
      if (rawTemplates is! List) {
        return _TemplatesPayload(templates: <SubmissionTemplate>[], order: <String>[]);
      }

      final templates = <SubmissionTemplate>[];
      for (final item in rawTemplates) {
        if (item is Map<String, dynamic>) {
          final storedTemplate = SubmissionTemplate.fromJson(item);
          if (storedTemplate.id.trim().isNotEmpty) templates.add(storedTemplate);
        }
      }

      final orderRaw = decoded['order'];
      final order = <String>[];
      if (orderRaw is List) {
        for (final templateId in orderRaw) {
          if (templateId is String && templateId.trim().isNotEmpty) {
            order.add(templateId);
          }
        }
      }

      return _TemplatesPayload(templates: templates, order: order);
    } catch (_) {
      return _TemplatesPayload(templates: <SubmissionTemplate>[], order: <String>[]);
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
