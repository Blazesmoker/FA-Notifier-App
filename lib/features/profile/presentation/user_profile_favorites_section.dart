import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/profile/presentation/profilefavs.dart';

class UserProfileFavoritesSection extends StatefulWidget {
  const UserProfileFavoritesSection({
    super.key,
    required this.sanitizedUsername,
  });

  final String sanitizedUsername;

  @override
  State<UserProfileFavoritesSection> createState() =>
      _UserProfileFavoritesSectionState();
}

class _UserProfileFavoritesSectionState
    extends State<UserProfileFavoritesSection>
    with AutomaticKeepAliveClientMixin<UserProfileFavoritesSection> {
  final GlobalKey<ProfileFavsSliverState> _favsKey =
      GlobalKey<ProfileFavsSliverState>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    final favsState = _favsKey.currentState;
    if (favsState == null) return;
    await favsState.refresh();
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
        key: const PageStorageKey<String>('profile-favorites-scroll'),
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
          ProfileFavsSliver(
            key: _favsKey,
            username: widget.sanitizedUsername,
          ),
        ],
      ),
    );
  }
}
