import 'package:FANotifier/features/profile/domain/post_shout_result.dart';

typedef ProfileShoutRepositoryFactory = ProfileShoutRepository Function();

abstract interface class ProfileShoutRepository {
  Future<void> initialize();

  Future<PostShoutResult> postShout({
    required String username,
    required String shout,
  });

  void close();
}
