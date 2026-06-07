import 'package:flutter/material.dart';

import 'package:FANotifier/features/profile/presentation/profilefavs.dart';

class UserProfileFavoritesSection extends StatelessWidget {
  const UserProfileFavoritesSection({
    super.key,
    required this.sanitizedUsername,
  });

  final String sanitizedUsername;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey<String>('profile-favorites-scroll'),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Favs',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        ProfileFavsSliver(username: sanitizedUsername),
      ],
    );
  }
}
