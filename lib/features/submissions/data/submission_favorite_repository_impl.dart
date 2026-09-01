import 'package:fanotifier/features/submissions/data/submission_favorite_remote_data_source.dart';
import 'package:fanotifier/features/submissions/data/submission_management_parser.dart';
import 'package:fanotifier/features/submissions/data/submission_management_remote_data_source.dart';
import 'package:fanotifier/features/submissions/domain/submission_management_models.dart';
import 'package:fanotifier/features/submissions/domain/submission_favorite_repository.dart';

class SubmissionFavoriteRepositoryImpl
    implements SubmissionFavoriteRepository {
  SubmissionFavoriteRepositoryImpl({
    SubmissionFavoriteRemoteDataSource? favoriteRemoteDataSource,
    SubmissionManagementRemoteDataSource? managementRemoteDataSource,
  })  : _favoriteRemoteDataSource =
            favoriteRemoteDataSource ??
                const SubmissionFavoriteRemoteDataSource(),
        _managementRemoteDataSource = managementRemoteDataSource ??
            const SubmissionManagementRemoteDataSource();

  static final Uri _favoritesUri =
      Uri.parse('https://www.furaffinity.net/controls/favorites/');

  final SubmissionFavoriteRemoteDataSource _favoriteRemoteDataSource;
  final SubmissionManagementRemoteDataSource _managementRemoteDataSource;

  @override
  Future<SubmissionFavoriteMutationResult> setFavoriteState({
    required String submissionId,
    required bool isFavorite,
    String? favUrl,
    String? unfavUrl,
    bool? sfwEnabled,
  }) {
    return _favoriteRemoteDataSource.setFavoriteState(
      submissionId: submissionId,
      isFavorite: isFavorite,
      favUrl: favUrl,
      unfavUrl: unfavUrl,
      sfwEnabled: sfwEnabled,
    );
  }

  @override
  Future<FaContentManagementResult> removeFavorites(
    Set<String> favoriteIds,
  ) async {
    if (favoriteIds.isEmpty) {
      return const FaContentManagementResult(
        success: false,
        message: 'Select at least one favorite.',
      );
    }
    if (favoriteIds.any((id) => !RegExp(r'^\d+$').hasMatch(id))) {
      return const FaContentManagementResult(
        success: false,
        message: 'The favorite selection contains an invalid ID.',
      );
    }
    final sortedIds = favoriteIds.toList()..sort();
    try {
      final response = await _managementRemoteDataSource.postAuthenticated(
        _favoritesUri,
        referer: _favoritesUri,
        fields: <FaManagementFormValue>[
          const FaManagementFormValue('page', '0'),
          for (final id in sortedIds)
            FaManagementFormValue('favorites[]', id),
          const FaManagementFormValue('do', 'delete'),
        ],
      );
      if (response.statusCode == 302) {
        return const FaContentManagementResult(
          success: true,
          statusCode: 302,
          changed: true,
        );
      }
      if (const <int>{408, 500, 502, 503, 504}
          .contains(response.statusCode)) {
        return FaContentManagementResult(
          success: false,
          statusCode: response.statusCode,
          indeterminate: true,
          message:
              'Fur Affinity returned HTTP ${response.statusCode} after the request was sent and may have removed some favorites. Refresh and review them before trying again.',
        );
      }
      return FaContentManagementResult(
        success: false,
        statusCode: response.statusCode,
        message: extractSubmissionManagementResponseMessage(response.body) ??
            'Fur Affinity returned HTTP ${response.statusCode} without confirming the action.',
      );
    } catch (error) {
      if (_managementRemoteDataSource.isRecoverable(error)) {
        return const FaContentManagementResult(
          success: false,
          indeterminate: true,
          message:
              'The request was interrupted. Fur Affinity may have removed some favorites. Refresh and review them before trying again.',
        );
      }
      return FaContentManagementResult(success: false, message: '$error');
    }
  }
}
