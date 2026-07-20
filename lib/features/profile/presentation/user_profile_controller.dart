import 'package:fanotifier/core/preferences/sfw_mode_preference.dart';
import 'package:fanotifier/features/profile/domain/fa_folder.dart';
import 'package:fanotifier/features/profile/domain/profile_folder_selection_resolver.dart';
import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/shared/fa/domain/user_link.dart';
import 'package:fanotifier/features/profile/domain/user_profile_api_models.dart';
import 'package:fanotifier/features/profile/domain/user_profile_load_result.dart';
import 'package:fanotifier/features/profile/domain/user_profile_repository.dart';
import 'package:fanotifier/shared/fa/fa_username.dart';

class UserProfileController {
  UserProfileController({
    required UserProfileRepository repository,
    SfwModePreference? sfwModePreference,
    required String nickname,
    String? initialFolderUrl,
    String? initialFolderName,
  })  : _repository = repository,
        _sfwModePreference = sfwModePreference ?? SfwModePreference(),
        sanitizedUsername = sanitizeFAUsername(nickname) {
    if (initialFolderUrl != null && initialFolderUrl.isNotEmpty) {
      selectedFolderUrl = initialFolderUrl;
      selectedFolderName = initialFolderName ?? selectedFolderName;
    }
  }

  final UserProfileRepository _repository;
  final SfwModePreference _sfwModePreference;

  bool sfwEnabled = true;
  String selectedFolderName = 'Main Gallery';
  String selectedFolderUrl = '';
  List<FaFolder> allFolders = <FaFolder>[];
  UserProfileParsed? _parsed;
  String sanitizedUsername;
  bool isLoading = true;
  String errorMessage = '';

  String? get profileBannerUrl => _parsed?.profileBannerUrl;
  String? get profileImageUrl => _parsed?.profileImageUrl;
  String? get profileDisplayName => _parsed?.profileDisplayName;
  String? get profileUserNamePart => _parsed?.profileUserNamePart;
  String? get symbolUsername => _parsed?.symbolUsername;
  String? get username => _parsed?.username;
  String? get userTitle => _parsed?.userTitle;
  String? get registrationDate => _parsed?.registrationDate;
  String? get userDescription => _parsed?.userDescription;
  bool get hasRealUserProfile => _parsed?.hasRealUserProfile ?? true;
  bool get isClassicMarkup => _parsed?.isClassicMarkup ?? false;
  bool get acceptingTrades => _parsed?.acceptingTrades ?? false;
  bool get acceptingCommissions => _parsed?.acceptingCommissions ?? false;
  List<String> get userIconBeforeUrls =>
      _parsed?.userIconBeforeUrls ?? const <String>[];
  List<String> get userIconAfterUrls =>
      _parsed?.userIconAfterUrls ?? const <String>[];
  int? get views => _parsed?.views;
  int? get submissions => _parsed?.submissions;
  int? get favs => _parsed?.favs;
  int? get commentsEarned => _parsed?.commentsEarned;
  int? get commentsMade => _parsed?.commentsMade;
  int? get journals => _parsed?.journals;
  bool get isWatching => _parsed?.isWatching ?? false;
  String? get watchLink => _parsed?.watchLink;
  String? get unwatchLink => _parsed?.unwatchLink;
  String? get unblockLink => _parsed?.unblockLink;
  String? get blockLink => _parsed?.blockLink;
  bool get isBlocked => _parsed?.isBlocked ?? false;
  bool get blockUsesPost => _parsed?.blockUsesPost ?? false;
  bool get unblockUsesPost => _parsed?.unblockUsesPost ?? false;
  String? get featuredImageUrl => _parsed?.featuredImageUrl;
  String? get featuredImageTitle => _parsed?.featuredImageTitle;
  String? get featuredPostNumber => _parsed?.featuredPostNumber;
  String? get userProfileImageUrl => _parsed?.userProfileImageUrl;
  String? get userProfilePostNumber => _parsed?.userProfilePostNumber;
  String? get userProfileTexts => _parsed?.userProfileTexts;
  List<Map<String, String>> get contactInformationLinks =>
      _parsed?.contactInformationLinks ?? const <Map<String, String>>[];
  List<UserLink> get recentWatchers =>
      _parsed?.recentWatchers ?? const <UserLink>[];
  int get recentWatchersCount => _parsed?.recentWatchersCount ?? 0;
  List<UserLink> get recentlyWatched =>
      _parsed?.recentlyWatched ?? const <UserLink>[];
  int get recentlyWatchedCount => _parsed?.recentlyWatchedCount ?? 0;
  List<Shout> get shouts => _parsed?.shouts ?? <Shout>[];
  String? get shoutPaginationKey => _parsed?.shoutPaginationKey;
  int get currentShoutPage => _parsed?.currentShoutPage ?? 1;
  int get totalShoutPages => _parsed?.totalShoutPages ?? 1;
  bool get isOwnProfile => _parsed?.isOwnProfile ?? false;

  Future<void> loadSfwEnabled() async {
    sfwEnabled = await _sfwModePreference.loadSfwEnabled();
  }

  Future<UserProfileLoadResult> loadProfile(String nickname) async {
    try {
      final result = await _repository.loadProfile(
        nickname: nickname,
        sfwEnabled: sfwEnabled,
      );
      sanitizedUsername = result.sanitizedUsername;
      _parsed = result.parsed;
      isLoading = false;
      return result;
    } on StateError catch (error) {
      errorMessage = error.message;
      isLoading = false;
      rethrow;
    } catch (error) {
      errorMessage = 'An error occurred: $error';
      isLoading = false;
      rethrow;
    }
  }

  void setWatching(bool value) {
    _parsed?.isWatching = value;
  }

  void addShouts(AdditionalShoutsPayload payload) {
    _parsed?.shouts.addAll(payload.newShouts);
    if (_parsed != null) {
      _parsed!.currentShoutPage = payload.nextPage;
    }
  }

  void updateFolders(List<FaFolder> folders) {
    final selected = resolveProfileFolderSelection(
      folders: folders,
      selectedName: selectedFolderName,
      selectedUrl: selectedFolderUrl,
    );
    selectedFolderName = selected.name;
    if (!areFaFolderUrlsEquivalent(selected.url, selectedFolderUrl)) {
      selectedFolderUrl = selected.url;
    }
    allFolders = folders;
  }

  void selectFolder(FaFolder folder) {
    selectedFolderName = folder.name;
    selectedFolderUrl = folder.url;
  }
}
