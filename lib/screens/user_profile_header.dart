import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    Key? key,
    required this.profileBannerUrl,
    required this.profileImageUrl,
    required this.profileDisplayName,
    required this.profileUserNamePart,
    required this.userTitle,
    required this.registrationDate,
    required this.isOwnProfile,
    required this.isWatching,
    required this.onEditProfile,
    required this.onWatchToggle,
    required this.onSendNote,
  }) : super(key: key);

  final String? profileBannerUrl;
  final String? profileImageUrl;
  final String? profileDisplayName;
  final String? profileUserNamePart;
  final String? userTitle;
  final String? registrationDate;
  final bool isOwnProfile;
  final bool isWatching;
  final VoidCallback onEditProfile;
  final VoidCallback onWatchToggle;
  final VoidCallback onSendNote;

  @override
  Widget build(BuildContext context) {
    const double avatarLeft = 16.0;
    const double avatarWidth = 90.0;
    const double marginBetweenAvatarAndText = 0.0;
    final double textLeftPadding = avatarLeft + avatarWidth + marginBetweenAvatarAndText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF111111),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 30.0,
                        child: Padding(
                          padding: EdgeInsets.only(left: textLeftPadding),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                _buildIcons(profileImageUrl, avatarWidth, avatarLeft),
                                if (profileDisplayName != null)
                                  Text(
                                    profileDisplayName!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                if ((profileUserNamePart ?? '').isNotEmpty)
                                  Text(
                                    profileUserNamePart!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20.0,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 24.0,
                        child: Visibility(
                          visible: true,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: 0.0,
                              left: textLeftPadding,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Text(
                                (userTitle?.isNotEmpty ?? false)
                                    ? userTitle!
                                    : " ",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16.0,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 8.0,
                          left: 0.0,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            registrationDate != null &&
                                    registrationDate!.isNotEmpty
                                ? 'Joined $registrationDate'
                                : '',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14.0,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (isOwnProfile)
                  SizedBox(
                    width: 100,
                    height: 38,
                    child: ElevatedButton(
                      onPressed: onEditProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(2),
                        ),
                        side: const BorderSide(
                          color: Color(0xFFE09321),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "Edit Profile",
                          style: TextStyle(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 100,
                        height: 38,
                        child: ElevatedButton(
                          onPressed: onWatchToggle,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                            side: const BorderSide(
                              color: Color(0xFFE09321),
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              isWatching ? "-Watch" : "+Watch",
                              style: const TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        width: 100,
                        height: 38,
                        child: ElevatedButton(
                          onPressed: onSendNote,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE09321),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "Note",
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIcons(String? imageUrl, double size, double left) {
    if (imageUrl == null) return const SizedBox();
    return Container(
      width: size,
      height: size,
      margin: EdgeInsets.only(right: left / 2),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.zero,
      ),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorWidget: (context, url, error) => Image.asset(
          'assets/images/defaultpic.gif',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

