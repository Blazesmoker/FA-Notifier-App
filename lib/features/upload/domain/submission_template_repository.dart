import 'package:FANotifier/features/upload/domain/submission_template.dart';

abstract interface class SubmissionTemplateRepository {
  Future<List<SubmissionTemplate>> loadTemplates();

  Future<SubmissionTemplate> saveTemplate({
    required String name,
    required SubmissionTemplateFields fields,
  });

  Future<void> deleteTemplate(String id);

  Future<void> renameTemplate(String id, String newName);

  Future<void> saveOrder(List<String> orderedIds);
}
