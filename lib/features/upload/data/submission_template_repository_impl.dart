import 'package:fanotifier/features/upload/data/submission_template_save_service.dart';
import 'package:fanotifier/features/upload/data/submission_template_store.dart';
import 'package:fanotifier/features/upload/domain/submission_template.dart';
import 'package:fanotifier/features/upload/domain/submission_template_repository.dart';

class SubmissionTemplateRepositoryImpl
    implements SubmissionTemplateRepository {
  factory SubmissionTemplateRepositoryImpl({
    SubmissionTemplateStore? store,
  }) {
    final resolvedStore = store ?? SubmissionTemplateStore();
    return SubmissionTemplateRepositoryImpl._(
      store: resolvedStore,
      saveService: SubmissionTemplateSaveService(store: resolvedStore),
    );
  }

  const SubmissionTemplateRepositoryImpl._({
    required SubmissionTemplateStore store,
    required SubmissionTemplateSaveService saveService,
  })  : _store = store,
        _saveService = saveService;

  final SubmissionTemplateStore _store;
  final SubmissionTemplateSaveService _saveService;

  @override
  Future<List<SubmissionTemplate>> loadTemplates() {
    return _store.loadTemplates();
  }

  @override
  Future<SubmissionTemplate> saveTemplate({
    required String name,
    required SubmissionTemplateFields fields,
  }) {
    return _saveService.save(name: name, fields: fields);
  }

  @override
  Future<void> deleteTemplate(String id) {
    return _store.deleteTemplate(id);
  }

  @override
  Future<void> renameTemplate(String id, String newName) {
    return _store.renameTemplate(id, newName);
  }

  @override
  Future<void> saveOrder(List<String> orderedIds) {
    return _store.saveOrder(orderedIds);
  }
}
