import 'package:flutter/material.dart';

import 'package:FANotifier/features/profile/presentation/profilescraps.dart';

class UserProfileScrapsSection extends StatefulWidget {
  const UserProfileScrapsSection({
    super.key,
    required this.sanitizedUsername,
  });

  final String sanitizedUsername;

  @override
  State<UserProfileScrapsSection> createState() =>
      _UserProfileScrapsSectionState();
}

class _UserProfileScrapsSectionState extends State<UserProfileScrapsSection>
    with AutomaticKeepAliveClientMixin<UserProfileScrapsSection> {
  final GlobalKey<ProfileScrapsSliverState> _scrapsKey =
      GlobalKey<ProfileScrapsSliverState>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    final scrapsState = _scrapsKey.currentState;
    if (scrapsState == null) return;
    await scrapsState.refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      color: const Color(0xFFE09321),
      backgroundColor: Colors.black,
      edgeOffset: 30.0,
      displacement: 70.0,
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const PageStorageKey<String>('profile-scraps-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
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
                    'Scraps',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          ProfileScrapsSliver(
            key: _scrapsKey,
            username: widget.sanitizedUsername,
          ),
        ],
      ),
    );
  }
}
