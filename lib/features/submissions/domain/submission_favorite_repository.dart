import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';

class SubmissionFavoriteMutationResult {
  const SubmissionFavoriteMutationResult({
    required this.success,
    required this.confirmedState,
    required this.changed,
    this.statusCode,
  });

  final bool success;
  final bool confirmedState;
  final bool changed;
  final int? statusCode;
}

abstract interface class SubmissionFavoriteRepository {
  Future<SubmissionFavoriteMutationResult> setFavoriteState({
    required String submissionId,
    required bool isFavorite,
    String? favUrl,
    String? unfavUrl,
    bool? sfwEnabled,
  });

  Future<FaContentManagementResult> removeFavorites(
    Set<String> favoriteIds,
  );
}
