import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:FANotifier/features/profile/presentation/profilejournals.dart';

class UserProfileJournalsSection extends StatefulWidget {
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
  State<UserProfileJournalsSection> createState() =>
      _UserProfileJournalsSectionState();
}

class _UserProfileJournalsSectionState extends State<UserProfileJournalsSection>
    with AutomaticKeepAliveClientMixin<UserProfileJournalsSection> {
  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    final journalsState = widget.journalsKey.currentState;
    if (journalsState == null) return;
    await journalsState.refreshJournals();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      color: const Color(0xFFE09321),
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const PageStorageKey<String>('profile-journals-scroll'),
        physics: Platform.isIOS
            ? const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              )
            : const AlwaysScrollableScrollPhysics(),
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
                    'Journals',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  if (widget.isOwnProfile)
                    ElevatedButton(
                      onPressed: widget.onCreateJournalPressed,
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
            key: widget.journalsKey,
            username: widget.sanitizedUsername,
          ),
        ],
      ),
    );
  }
}
