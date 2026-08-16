import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:visibility_detector/visibility_detector.dart';

import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/shared/fa/domain/user_link.dart';
import 'package:fanotifier/features/profile/presentation/user_description_webview.dart';
import 'package:fanotifier/features/profile/presentation/user_grid_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_components.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_shouts_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_styles.dart';

class UserProfileHomeSection extends StatelessWidget {
  const UserProfileHomeSection({
    super.key,
    required this.hasRealUserProfile,
    required this.userDescription,
    required this.webViewKey,
    required this.sanitizedUsername,
    required this.onDescriptionLongPressStart,
    required this.enableScrollPerformancePause,
    required this.onWebViewLoaded,
    required this.featuredImageUrl,
    required this.featuredImageTitle,
    required this.featuredPostNumber,
    required this.onOpenPost,
    required this.userProfileImageUrl,
    required this.userProfilePostNumber,
    required this.userProfileTexts,
    required this.isClassicMarkup,
    required this.acceptingTrades,
    required this.acceptingCommissions,
    required this.onHandleFALink,
    required this.contactInformationLinks,
    required this.onLaunchUrl,
    required this.recentWatchers,
    required this.recentWatchersCount,
    required this.recentlyWatched,
    required this.recentlyWatchedCount,
    required this.shouts,
    required this.isOwnProfile,
    required this.isShoutSelectionMode,
    required this.selectedShoutCount,
    required this.currentShoutPage,
    required this.totalShoutPages,
    required this.isLoadingMoreShouts,
    required this.onOpenPostShout,
    required this.onLoadMoreShouts,
    required this.onConfirmDeleteShout,
    required this.onToggleShoutSelectionMode,
    required this.onToggleShoutSelection,
  });

  final bool hasRealUserProfile;
  final String? userDescription;
  final GlobalKey<UserDescriptionWebViewState> webViewKey;
  final String sanitizedUsername;
  final GestureLongPressStartCallback onDescriptionLongPressStart;
  final bool enableScrollPerformancePause;
  final ValueChanged<bool> onWebViewLoaded;

  final String? featuredImageUrl;
  final String? featuredImageTitle;
  final String? featuredPostNumber;
  final void Function(
      BuildContext context, String imageUrl, String uniqueNumber) onOpenPost;

  final String? userProfileImageUrl;
  final String? userProfilePostNumber;
  final String? userProfileTexts;
  final bool isClassicMarkup;
  final bool acceptingTrades;
  final bool acceptingCommissions;
  final Future<void> Function(BuildContext context, String url) onHandleFALink;

  final List<Map<String, String>> contactInformationLinks;
  final void Function(String url) onLaunchUrl;

  final List<UserLink> recentWatchers;
  final int recentWatchersCount;
  final List<UserLink> recentlyWatched;
  final int recentlyWatchedCount;

  final List<Shout> shouts;
  final bool isOwnProfile;
  final bool isShoutSelectionMode;
  final int selectedShoutCount;
  final int currentShoutPage;
  final int totalShoutPages;
  final bool isLoadingMoreShouts;
  final Future<void> Function(BuildContext context) onOpenPostShout;
  final Future<void> Function() onLoadMoreShouts;
  final Future<void> Function(int index, Shout shout) onConfirmDeleteShout;
  final void Function() onToggleShoutSelectionMode;
  final void Function(Shout shout) onToggleShoutSelection;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey<String>('profile-home-scroll'),
      physics: Platform.isIOS ? const ClampingScrollPhysics() : null,
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (hasRealUserProfile &&
                  userDescription != null &&
                  userDescription!.trim().isNotEmpty)
                GestureDetector(
                  onLongPressStart: onDescriptionLongPressStart,
                  child: enableScrollPerformancePause
                      ? VisibilityDetector(
                          key: ObjectKey(webViewKey),
                          onVisibilityChanged: (info) {
                            final state = webViewKey.currentState;
                            if (state == null) {
                              return;
                            }
                            if (info.visibleFraction > 0.15) {
                              state.resumeWebView(
                                reason: UserDescriptionWebViewPauseReason
                                    .visibility,
                              );
                            } else {
                              state.pauseWebView(
                                reason: UserDescriptionWebViewPauseReason
                                    .visibility,
                              );
                            }
                          },
                          child: UserDescriptionWebView(
                            key: webViewKey,
                            sanitizedUsername: sanitizedUsername,
                            initialHtml: userDescription,
                            forceHybridComposition: false,
                            enableTextSelection: false,
                            enableScrollPerformancePause:
                                enableScrollPerformancePause,
                            disableIosScrolling: true,
                            onWebViewLoaded: onWebViewLoaded,
                          ),
                        )
                      : UserDescriptionWebView(
                          key: webViewKey,
                          sanitizedUsername: sanitizedUsername,
                          initialHtml: userDescription,
                          forceHybridComposition: false,
                          enableTextSelection: false,
                          enableScrollPerformancePause: false,
                          disableIosScrolling: true,
                          onWebViewLoaded: onWebViewLoaded,
                        ),
                ),
              const SizedBox(height: 16.0),
              if (featuredImageUrl != null &&
                  featuredImageUrl!.isNotEmpty &&
                  featuredImageTitle != null &&
                  featuredImageTitle!.isNotEmpty &&
                  featuredPostNumber != null &&
                  featuredPostNumber!.isNotEmpty) ...[
                FeaturedSubmissionSection(
                  imageUrl: featuredImageUrl!,
                  title: featuredImageTitle!,
                  onTap: () {
                    onOpenPost(context, featuredImageUrl!, featuredPostNumber!);
                  },
                ),
                const SizedBox(height: 8.0),
              ],
              if (hasRealUserProfile &&
                  userProfileTexts != null &&
                  userProfileTexts!.isNotEmpty &&
                  userProfileTexts != 'No additional profile information.')
                UserProfileAdditionalInfoSection(
                  userProfileImageUrl: userProfileImageUrl,
                  userProfilePostNumber: userProfilePostNumber,
                  userProfileTexts: userProfileTexts!,
                  isClassicMarkup: isClassicMarkup,
                  acceptingTrades: acceptingTrades,
                  acceptingCommissions: acceptingCommissions,
                  onOpenPost: onOpenPost,
                  onHandleFALink: onHandleFALink,
                ),
              const SizedBox(height: 8.0),
              if (contactInformationLinks.isNotEmpty)
                ContactInformationSection(
                  contacts: contactInformationLinks,
                  onLinkTap: onLaunchUrl,
                ),
              const SizedBox(height: 8.0),
              if (recentWatchers.isNotEmpty || recentWatchersCount > 0)
                UserGridSection(
                  title: 'Recent Watchers',
                  viewListText: 'Watched by $recentWatchersCount',
                  totalUsersCount: recentWatchersCount,
                  users: recentWatchers,
                  sanitizedUsername: sanitizedUsername,
                ),
              const SizedBox(height: 8.0),
              if (recentlyWatched.isNotEmpty || recentlyWatchedCount > 0)
                UserGridSection(
                  title: 'Recently Watched',
                  viewListText: 'Watching $recentlyWatchedCount',
                  totalUsersCount: recentlyWatchedCount,
                  users: recentlyWatched,
                  sanitizedUsername: sanitizedUsername,
                ),
              const SizedBox(height: 8.0),
              UserProfileShoutsSection(
                shouts: shouts,
                isOwnProfile: isOwnProfile,
                isSelectionMode: isShoutSelectionMode,
                selectedShoutCount: selectedShoutCount,
                currentShoutPage: currentShoutPage,
                totalShoutPages: totalShoutPages,
                isLoadingMoreShouts: isLoadingMoreShouts,
                onOpenPostShout: onOpenPostShout,
                onLoadMoreShouts: onLoadMoreShouts,
                onConfirmDeleteShout: onConfirmDeleteShout,
                onToggleSelectionMode: onToggleShoutSelectionMode,
                onToggleShoutSelection: onToggleShoutSelection,
              ),
              const SizedBox(height: 8.0),
            ]),
          ),
        ),
      ],
    );
  }
}

class UserProfileAdditionalInfoSection extends StatelessWidget {
  const UserProfileAdditionalInfoSection({
    super.key,
    required this.userProfileImageUrl,
    required this.userProfilePostNumber,
    required this.userProfileTexts,
    required this.isClassicMarkup,
    required this.acceptingTrades,
    required this.acceptingCommissions,
    required this.onOpenPost,
    required this.onHandleFALink,
  });

  final String? userProfileImageUrl;
  final String? userProfilePostNumber;
  final String userProfileTexts;
  final bool isClassicMarkup;
  final bool acceptingTrades;
  final bool acceptingCommissions;
  final void Function(
      BuildContext context, String imageUrl, String uniqueNumber) onOpenPost;
  final Future<void> Function(BuildContext context, String url) onHandleFALink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'User Profile',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 8.0),
            if (userProfileImageUrl != null)
              GestureDetector(
                onTap: () {
                  if (userProfilePostNumber != null) {
                    onOpenPost(
                        context, userProfileImageUrl!, userProfilePostNumber!);
                  }
                },
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: FaNetworkImage(
                      userProfileImageUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        }
                        return const SizedBox(
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8.0),
            if (isClassicMarkup)
              Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "Accepting Trades: ${acceptingTrades ? "Yes" : "No"}",
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Accepting Commissions: ${acceptingCommissions ? "Yes" : "No"}",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8.0),
            html_pkg.Html(
              data: userProfileTexts,
              style: userProfileHtmlStylesCompact(),
              extensions: buildUserProfileBBCodeExtensions(),
              onLinkTap: (url, _, _) => onHandleFALink(context, url!),
            ),
          ],
        ),
      ),
    );
  }
}
