import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/profile/presentation/profile_animated_media_visibility.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

const double _profileAvatarLeft = 16.0;
const double _profileAvatarSize = 90.0;
const double _profileAvatarBorderWidth = 2.0;
const double _profileAvatarMinScale = 0.53;
const double _profileAvatarScrollDownDistance = 16.0;
const double _profileAvatarScrollDownEnd = 64.0;

Widget buildProfileAnimatedAvatar(
  double offset,
  Widget avatarChild, {
  required bool animationEnabled,
  required BuildContext context,
}) {
  final double scaleProgress =
      (offset / _profileAvatarScrollDownEnd).clamp(0.0, 1.0).toDouble();
  final double scale = 1.0 - ((1.0 - _profileAvatarMinScale) * scaleProgress);
  final double scrollPastShrink =
      max(0.0, offset - _profileAvatarScrollDownEnd);
  final double translateY =
      (_profileAvatarScrollDownDistance * scaleProgress) - scrollPastShrink;

  return Positioned(
    key: const ValueKey<String>('profileAvatar'),
    bottom: -_profileAvatarSize / 1.5 - _profileAvatarBorderWidth,
    left: _profileAvatarLeft - _profileAvatarBorderWidth,
    child: TickerMode(
      enabled: TickerMode.valuesOf(context).enabled && animationEnabled,
      child: Transform.translate(
        offset: Offset(0.0, translateY),
        child: Transform.scale(
          scale: scale,
          child: avatarChild,
        ),
      ),
    ),
  );
}

Widget buildProfileAvatarImage({
  required String? profileImageUrl,
  required int profileMediaRevision,
  required GlobalKey<ProfileAnimatedMediaVisibilityState> avatarMediaVisibilityKey,
  required ValueNotifier<bool> profileAvatarBorderVisible,
}) {
  final double outerAvatarSize =
      _profileAvatarSize + (_profileAvatarBorderWidth * 2.0);
  final Widget avatarImage = profileImageUrl == null || profileImageUrl.isEmpty
          ? Image.asset(
              'assets/images/defaultpic.gif',
              width: _profileAvatarSize,
              height: _profileAvatarSize,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
          : FaNetworkImage(
              profileImageUrl,
              key: ValueKey(
                'profile-avatar-$profileImageUrl-$profileMediaRevision',
              ),
              width: _profileAvatarSize,
              height: _profileAvatarSize,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return SizedBox(
                  width: _profileAvatarSize / 2,
                  height: _profileAvatarSize / 2,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Image.asset(
                  'assets/images/defaultpic.gif',
                  width: _profileAvatarSize,
                  height: _profileAvatarSize,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              },
            );

  return ProfileAnimatedMediaVisibility(
    key: avatarMediaVisibilityKey,
    lookAhead: 90.0,
    child: RepaintBoundary(
      child: GestureDetector(
        onTap: () {},
        child: SizedBox(
          width: outerAvatarSize,
          height: outerAvatarSize,
          child: ValueListenableBuilder<bool>(
            valueListenable: profileAvatarBorderVisible,
            child: Positioned(
              left: _profileAvatarBorderWidth,
              top: _profileAvatarBorderWidth,
              child: avatarImage,
            ),
            builder: (context, showBorder, child) {
              return Stack(
                children: [
                  child!,
                  if (showBorder)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF111111),
                              width: _profileAvatarBorderWidth,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
