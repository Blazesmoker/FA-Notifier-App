import 'package:FANotifier/features/journals/data/openjournal_api_service.dart';
import 'package:FANotifier/features/journals/domain/openjournal_fetch_result.dart';
import 'package:FANotifier/features/journals/domain/openjournal_repository.dart';

class OpenJournalRepositoryImpl implements OpenJournalRepository {
  const OpenJournalRepositoryImpl({required OpenJournalApiService api})
      : _api = api;

  final OpenJournalApiService _api;

  @override
  Future<OpenJournalFetchResult> fetchJournal(String uniqueNumber) {
    return _api.fetchJournal(uniqueNumber);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCommentsFromBody(String body) {
    return _api.fetchCommentsFromBody(body);
  }
}
