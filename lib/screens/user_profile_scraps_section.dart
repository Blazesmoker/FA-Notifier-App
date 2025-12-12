import 'package:flutter/material.dart';

import 'profilescraps.dart';

class UserProfileScrapsSection extends StatelessWidget {
  const UserProfileScrapsSection({
    super.key,
    required this.sanitizedUsername,
  });

  final String sanitizedUsername;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Scraps',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        ProfileScrapsSliver(username: sanitizedUsername),
      ],
    );
  }
}


