import 'package:flutter/material.dart';

import 'profilejournals.dart';

class UserProfileJournalsSection extends StatelessWidget {
  const UserProfileJournalsSection({
    super.key,
    required this.sanitizedUsername,
    required this.isOwnProfile,
    required this.journalsKey,
    required this.onCreateJournalPressed,
  });

  final String sanitizedUsername;
  final bool isOwnProfile;
  final GlobalKey<ProfileJournalsState> journalsKey;
  final VoidCallback onCreateJournalPressed;

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
                  'Journals',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (isOwnProfile)
                  ElevatedButton(
                    onPressed: onCreateJournalPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFE09321),
                    ),
                    child: const Text(
                      'Create Journal',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        ProfileJournals(
          key: journalsKey,
          username: sanitizedUsername,
        ),
      ],
    );
  }
}


