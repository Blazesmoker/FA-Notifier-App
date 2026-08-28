import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:fanotifier/features/profile/presentation/profile_bulk_selection_bar.dart';
import 'package:fanotifier/features/profile/presentation/profilefavs.dart';

class UserProfileFavoritesSection extends StatefulWidget {
  const UserProfileFavoritesSection({
    super.key,
    required this.sanitizedUsername,
    required this.isOwnProfile,
    required this.onSelectionLayoutChanged,
  });

  final String sanitizedUsername;
  final bool isOwnProfile;
  final ProfileBulkSelectionLayoutChanged onSelectionLayoutChanged;

  @override
  State<UserProfileFavoritesSection> createState() =>
      _UserProfileFavoritesSectionState();
}

class _UserProfileFavoritesSectionState
    extends State<UserProfileFavoritesSection>
    with AutomaticKeepAliveClientMixin<UserProfileFavoritesSection> {
  final GlobalKey<ProfileFavsSliverState> _favsKey =
      GlobalKey<ProfileFavsSliverState>();
  final GlobalKey _bulkSelectionBarKey = GlobalKey();
  bool _selectionMode = false;
  bool _isApplying = false;
  int _selectedCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant UserProfileFavoritesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.isOwnProfile ||
            oldWidget.sanitizedUsername != widget.sanitizedUsername) &&
        _selectionMode) {
      _selectionMode = false;
      _isApplying = false;
      _selectedCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onSelectionLayoutChanged(false, 0);
      });
    }
  }

  Future<void> _refresh() async {
    final favsState = _favsKey.currentState;
    if (favsState == null) return;
    await favsState.refresh();
  }

  void _toggleSelectionMode() {
    if (_isApplying) return;
    final nextSelectionMode = !_selectionMode;
    if (_selectionMode) _favsKey.currentState?.clearSelection();
    setState(() {
      _selectionMode = nextSelectionMode;
      _selectedCount = 0;
    });
    widget.onSelectionLayoutChanged(nextSelectionMode, 0);
  }

  void _toggleAllDisplayedSelection() {
    if (_isApplying) return;
    _favsKey.currentState?.toggleAllDisplayedSelection();
  }

  void _scheduleSelectionLayoutReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_selectionMode) return;
      final renderObject =
          _bulkSelectionBarKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox) return;
      widget.onSelectionLayoutChanged(true, renderObject.size.height);
    });
  }

  void _onSelectionCountChanged(int count) {
    if (!mounted || count == _selectedCount) return;
    setState(() => _selectedCount = count);
  }

  Future<void> _confirmAndRemove() async {
    final favsState = _favsKey.currentState;
    final selectedCount = favsState?.selectedCount ?? 0;
    if (favsState == null || selectedCount == 0 || _isApplying) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: const Color(0xFF202020),
              title: const Text('Remove favorites?'),
              content: Text(
                'Remove $selectedCount selected ${selectedCount == 1 ? 'favorite' : 'favorites'} from your Fur Affinity account?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD64B4B),
                  ),
                  child: const Text('Remove'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _isApplying = true);
    final result = await favsState.removeSelectedFavorites();
    if (!mounted) return;
    if (result.success) {
      favsState.clearSelection();
      setState(() {
        _selectionMode = false;
        _isApplying = false;
        _selectedCount = 0;
      });
      widget.onSelectionLayoutChanged(false, 0);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$selectedCount ${selectedCount == 1 ? 'favorite was' : 'favorites were'} removed.',
          ),
        ),
      );
      return;
    }
    setState(() => _isApplying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: result.indeterminate
            ? const Color(0xFFE09321)
            : const Color(0xFF9B3434),
        content: Text(result.message ?? 'Fur Affinity did not confirm the action.'),
        duration: result.indeterminate
            ? const Duration(seconds: 8)
            : const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_selectionMode) _scheduleSelectionLayoutReport();
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: _isApplying,
          child: RefreshIndicator(
            color: const Color(0xFFE09321),
            backgroundColor: Colors.black,
            edgeOffset: 30.0,
            displacement: 70.0,
            onRefresh: _selectionMode ? () async {} : _refresh,
            child: CustomScrollView(
              key: const PageStorageKey<String>('profile-favorites-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverOverlapInjector(
                  handle:
                      NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Favs',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (widget.isOwnProfile)
                          IconButton(
                            key: const ValueKey(
                              'profile-favs-selection-button',
                            ),
                            tooltip: _selectionMode
                                ? 'Cancel favorite selection'
                                : 'Select favorites to remove',
                            onPressed:
                                _isApplying ? null : _toggleSelectionMode,
                            icon: Icon(
                              _selectionMode
                                  ? Icons.close
                                  : Symbols.heart_minus,
                              color: const Color(0xFFE09321),
                            ),
                          ),
                        if (widget.isOwnProfile && _selectionMode)
                          IconButton(
                            key: const ValueKey(
                              'profile-favs-select-all-button',
                            ),
                            tooltip:
                                'Select or deselect all displayed favorites',
                            onPressed: _isApplying
                                ? null
                                : _toggleAllDisplayedSelection,
                            icon: Icon(
                              _selectedCount == 0
                                  ? Icons.library_add_check_outlined
                                  : Icons.library_add_check,
                              size: 22,
                              color: const Color(0xFFE09321),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ProfileFavsSliver(
                  key: _favsKey,
                  username: widget.sanitizedUsername,
                  selectionMode: _selectionMode,
                  onSelectionCountChanged: _onSelectionCountChanged,
                ),
                if (_selectionMode)
                  const SliverToBoxAdapter(child: SizedBox(height: 104)),
              ],
            ),
          ),
        ),
        if (_selectionMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ProfileBulkSelectionBar(
              key: _bulkSelectionBarKey,
              selectedCount: _selectedCount,
              actionLabel: 'Unfavorite',
              actionIcon: Icons.heart_broken_outlined,
              destructive: true,
              isApplying: _isApplying,
              onToggleAll: _toggleAllDisplayedSelection,
              onCancel: _toggleSelectionMode,
              onApply: _confirmAndRemove,
            ),
          ),
      ],
    );
  }
}
