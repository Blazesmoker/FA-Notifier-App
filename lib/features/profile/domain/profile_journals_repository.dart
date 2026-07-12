import 'package:FANotifier/features/profile/domain/profile_journals_models.dart';

abstract interface class ProfileJournalsRepository {
  Future<ProfileJournalsPageData> fetchJournalsPage({
    required String username,
    required int pageNumber,
  });
}
