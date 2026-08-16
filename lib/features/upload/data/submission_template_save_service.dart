import 'package:flutter/foundation.dart';

import 'package:fanotifier/features/upload/data/submission_template_store.dart';
import 'package:fanotifier/features/upload/domain/submission_template.dart';

class SubmissionTemplateSaveService {
  const SubmissionTemplateSaveService({
    required this._store,
  });

  final SubmissionTemplateStore _store;

  Future<SubmissionTemplate> save({
    required String name,
    required SubmissionTemplateFields fields,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final template = SubmissionTemplate(
      id: now.toString(),
      name: name,
      updatedAtMs: now,
      fields: fields,
    );

    debugPrint('Saving template: ${template.name} (id: ${template.id})');
    await _store.upsertTemplate(template);
    debugPrint('Template saved successfully');
    return template;
  }
}
