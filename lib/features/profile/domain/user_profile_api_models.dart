import 'package:FANotifier/features/profile/domain/shout.dart';
import 'package:FANotifier/features/profile/domain/user_link.dart';

class UserProfileParsed {
  UserProfileParsed({
    required this.profileBannerUrl,
    required this.profileImageUrl,
    required this.profileDisplayName,
    required this.profileUserNamePart,
    required this.symbolUsername,
    required this.username,
    required this.userTitle,
    required this.registrationDate,
    required this.userDescription,
    required this.hasRealUserProfile,
    required this.isClassicMarkup,
    required this.acceptingTrades,
    required this.acceptingCommissions,
    required this.userIconBeforeUrls,
    required this.userIconAfterUrls,
    required this.views,
    required this.submissions,
    required this.favs,
    required this.commentsEarned,
    required this.commentsMade,
    required this.journals,
    required this.featuredImageUrl,
    required this.featuredImageTitle,
    required this.featuredPostNumber,
    required this.userProfileImageUrl,
    required this.userProfilePostNumber,
    required this.userProfileTexts,
    required this.contactInformationLinks,
    required this.recentWatchers,
    required this.recentWatchersCount,
    required this.recentlyWatched,
    required this.recentlyWatchedCount,
    required this.shouts,
    required this.shoutPaginationKey,
    required this.currentShoutPage,
    required this.totalShoutPages,
    required this.watchLink,
    required this.unwatchLink,
    required this.blockLink,
    required this.unblockLink,
    required this.blockUsesPost,
    required this.unblockUsesPost,
    required this.isWatching,
    required this.isBlocked,
    required this.isOwnProfile,
  });

  String? profileBannerUrl;
  String? profileImageUrl;
  String? profileDisplayName;
  String? profileUserNamePart;
  String? symbolUsername;
  String username;
  String? userTitle;
  String? registrationDate;
  String? userDescription;
  bool hasRealUserProfile;
  bool isClassicMarkup;
  bool acceptingTrades;
  bool acceptingCommissions;
  List<String> userIconBeforeUrls;
  List<String> userIconAfterUrls;
  int? views;
  int? submissions;
  int? favs;
  int? commentsEarned;
  int? commentsMade;
  int? journals;
  String? featuredImageUrl;
  String? featuredImageTitle;
  String? featuredPostNumber;
  String? userProfileImageUrl;
  String? userProfilePostNumber;
  String? userProfileTexts;
  List<Map<String, String>> contactInformationLinks;
  List<UserLink> recentWatchers;
  int recentWatchersCount;
  List<UserLink> recentlyWatched;
  int recentlyWatchedCount;
  List<Shout> shouts;
  String? shoutPaginationKey;
  int currentShoutPage;
  int totalShoutPages;
  String? watchLink;
  String? unwatchLink;
  String? blockLink;
  String? unblockLink;
  bool blockUsesPost;
  bool unblockUsesPost;
  bool isWatching;
  bool isBlocked;
  bool isOwnProfile;
}

class UserProfileFetchPayload {
  final String sanitizedUsername;
  final String htmlBody;
  final String sfwValue;

  UserProfileFetchPayload({
    required this.sanitizedUsername,
    required this.htmlBody,
    required this.sfwValue,
  });
}

class ShoutPagePayload {
  final String body;
  final int nextPage;

  ShoutPagePayload({
    required this.body,
    required this.nextPage,
  });
}

class WatchUnwatchResult {
  final bool success;
  final bool missingCookies;
  final int? statusCode;
  final Object? error;

  const WatchUnwatchResult({
    required this.success,
    required this.missingCookies,
    this.statusCode,
    this.error,
  });
}

class BlockUnblockResult {
  final bool success;
  final bool missingCookies;
  final int? statusCode;
  final Object? error;

  const BlockUnblockResult({
    required this.success,
    required this.missingCookies,
    this.statusCode,
    this.error,
  });
}

class DeleteShoutResult {
  final bool success;
  final bool missingCookies;
  final int? statusCode;
  final Object? error;

  const DeleteShoutResult({
    required this.success,
    required this.missingCookies,
    this.statusCode,
    this.error,
  });
}

class AdditionalShoutsPayload {
  final List<Shout> newShouts;
  final int nextPage;

  const AdditionalShoutsPayload({
    required this.newShouts,
    required this.nextPage,
  });
}

class ControlsShoutsPageInfo {
  final int page;
  final int totalPages;
  final Set<String> shoutIds;
  final List<ControlsShoutEntry> entries;

  const ControlsShoutsPageInfo({
    required this.page,
    required this.totalPages,
    required this.shoutIds,
    required this.entries,
  });
}

class ControlsShoutEntry {
  final String id;
  final int page;
  final String avatarUrl;
  final String profileNickname;
  final String popupDateFull;
  final String messageHtml;

  const ControlsShoutEntry({
    required this.id,
    required this.page,
    required this.avatarUrl,
    required this.profileNickname,
    required this.popupDateFull,
    required this.messageHtml,
  });
}

class ResolvedControlsShout {
  final Shout shout;
  final String id;
  final int page;

  const ResolvedControlsShout({
    required this.shout,
    required this.id,
    required this.page,
  });
}
