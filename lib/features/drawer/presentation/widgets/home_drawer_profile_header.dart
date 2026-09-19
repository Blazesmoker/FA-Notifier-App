import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/fa/domain/user_profile.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/shared/widgets/pulsating_loading_indicator.dart';
import 'package:fanotifier/shared/theme/app_theme.dart';

Widget buildHomeDrawerProfileHeader({
  required UserProfile? userProfile,
  required bool isUserProfileLoading,
  required AnimationController? Function() animationController,
  required int avatarRevision,
  required List<Widget> badgesWithSpacing,
  required VoidCallback onProfileTap,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.only(top: 0.0),
    color: Color(0xFF111111),
    child: Container(
      padding: const EdgeInsets.only(
        right: 0.0,
        left: 0.0,
        top: 4.0,
        bottom: 4.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onProfileTap,
                child:
                    isUserProfileLoading &&
                        (userProfile == null ||
                            userProfile.profileImageUrl.isEmpty)
                    ? const SizedBox(
                        width: 120,
                        height: 120,
                        child: Center(
                          child: PulsatingLoadingIndicator(
                            size: 58.0,
                            assetPath: 'assets/icons/fathemed.png',
                          ),
                        ),
                      )
                    : userProfile != null &&
                          userProfile.profileImageUrl.isNotEmpty
                    ? AnimatedBuilder(
                        animation: animationController()!,
                        builder: (BuildContext context, Widget? child) {
                          return ScaleTransition(
                            scale: AlwaysStoppedAnimation<double>(
                              1.0 - (animationController()!.value) * 0.2,
                            ),
                            child: RotationTransition(
                              turns: const AlwaysStoppedAnimation<double>(0.0),
                              child: Container(
                                height: 110,
                                width: 110,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12.0),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: AppTheme.grey.withValues(
                                        alpha: 0.0,
                                      ),
                                      offset: const Offset(2.0, 4.0),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: FaNetworkImage(
                                  userProfile.profileImageUrl,
                                  key: ValueKey(
                                    'drawer-avatar-${userProfile.profileImageUrl}-$avatarRevision',
                                  ),
                                  fit: BoxFit.cover,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return const Center(
                                          child: PulsatingLoadingIndicator(
                                            size: 58.0,
                                            assetPath:
                                                'assets/icons/fathemed.png',
                                          ),
                                        );
                                      },
                                  errorBuilder: (context, error, stackTrace) {
                                    if (error.toString().contains('404')) {
                                      return Image.asset(
                                        'assets/images/defaultpic.gif',
                                        fit: BoxFit.cover,
                                      );
                                    } else {
                                      return const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.white,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : ClipRRect(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(60.0),
                        ),
                        child: Image.asset(
                          'assets/images/defaultpic.gif',
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 4.0, color: Colors.black, thickness: 4.0),
          const SizedBox(height: 8),
          Text(
            userProfile?.username ?? 'Username',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 3.0, color: Colors.black, thickness: 3.0),
          const SizedBox(height: 6),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: badgesWithSpacing,
            ),
          ),
        ],
      ),
    ),
  );
}
