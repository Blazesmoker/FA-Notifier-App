import 'package:like_button/like_button.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/core/analytics/app_screen.dart';
import 'package:fanotifier/features/notes/presentation/new_message_screen.dart';
import 'package:fanotifier/features/profile/domain/profile_section.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';

Widget buildSubmissionActionBar({
  required BuildContext context,
  required String? Function() getLinkUsername,
  required bool isFavorited,
  required bool showTagsSection,
  required Future<bool> Function(bool) onToggleFavorite,
  required VoidCallback onToggleTags,
  required VoidCallback onShare,
}) {
  return SizedBox(
    height: 50,
    child: Row(
      mainAxisAlignment:
          MainAxisAlignment
              .spaceEvenly,
      children: [
        Expanded(
          child: IconButton(
            icon: const Icon(
              Icons.mail_outline,
              size: 26,
              color: Colors.grey,
            ),
            onPressed: () {
              if (getLinkUsername() !=
                  null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings:
                        const AnalyticsRouteSettings(
                      AppScreens
                          .newNote,
                    ),
                    builder: (context) =>
                        NewMessageScreen(
                      recipient:
                          getLinkUsername()!,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(
                        context)
                    .showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Recipient username is unavailable.'),
                    backgroundColor:
                        Colors.red,
                  ),
                );
              }
            },
            splashRadius: 24,
          ),
        ),
        Expanded(
          child: IconButton(
            icon: const Icon(
              Icons
                  .photo_library_outlined,
              size: 26,
              color: Colors.grey,
            ),
            onPressed: () {
              if (getLinkUsername() !=
                  null) {
                Navigator.push(
                  context,
                  UserProfileScreen
                      .route(
                    nickname:
                        getLinkUsername()!,
                    initialSection:
                        ProfileSection
                            .gallery,
                  ),
                );
              } else {
                ScaffoldMessenger.of(
                        context)
                    .showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Username is unavailable.'),
                    backgroundColor:
                        Colors.red,
                  ),
                );
              }
            },
            splashRadius: 24,
          ),
        ),
        Expanded(
          child: Center(
            child: LikeButton(
              isLiked: isFavorited,
              size: 26,
              circleColor:
                  const CircleColor(
                start: Colors.red,
                end: Colors.redAccent,
              ),
              bubblesColor:
                  const BubblesColor(
                dotPrimaryColor:
                    Colors.red,
                dotSecondaryColor:
                    Colors.redAccent,
              ),
              likeBuilder:
                  (bool isLiked) {
                return Icon(
                  isLiked
                      ? Icons.favorite
                      : Icons
                          .favorite_border,
                  color: isLiked
                      ? Colors.red
                      : Colors.grey,
                  size: 26,
                );
              },
              animationDuration:
                  const Duration(
                      milliseconds:
                          500),
              onTap: onToggleFavorite,
            ),
          ),
        ),
        Expanded(
          child: IconButton(
            icon: Icon(
              Icons.numbers,
              size: 26,
              color: showTagsSection
                  ? const Color(
                      0xFFE09321)
                  : Colors.grey,
            ),
            onPressed: onToggleTags,
            splashRadius: 24,
          ),
        ),
        Expanded(
          child: IconButton(
            icon: const Icon(
              Icons.share_outlined,
              size: 26,
              color: Colors.grey,
            ),
            onPressed: onShare,
            splashRadius: 24,
          ),
        ),
      ],
    ),
  );
}
