import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/profile/presentation/profile_bulk_selection_bar.dart';
import 'package:fanotifier/features/profile/presentation/profilescraps.dart';

class UserProfileScrapsSection extends StatefulWidget {
  const UserProfileScrapsSection({
    super.key,
    required this.sanitizedUsername,
    required this.isOwnProfile,
    required this.onSelectionLayoutChanged,
  });

  final String sanitizedUsername;
  final bool isOwnProfile;
  final ProfileBulkSelectionLayoutChanged onSelectionLayoutChanged;

  @override
  State<UserProfileScrapsSection> createState() =>
      _UserProfileScrapsSectionState();
}

class _UserProfileScrapsSectionState extends State<UserProfileScrapsSection>
    with AutomaticKeepAliveClientMixin<UserProfileScrapsSection> {
  final GlobalKey<ProfileScrapsSliverState> _scrapsKey =
      GlobalKey<ProfileScrapsSliverState>();
  final GlobalKey _bulkSelectionBarKey = GlobalKey();
  bool _selectionMode = false;
  bool _isApplying = false;
  int _selectedCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant UserProfileScrapsSection oldWidget) {
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
    final scrapsState = _scrapsKey.currentState;
    if (scrapsState == null) return;
    await scrapsState.refresh();
  }

  void _toggleSelectionMode() {
    if (_isApplying) return;
    final nextSelectionMode = !_selectionMode;
    if (_selectionMode) _scrapsKey.currentState?.clearSelection();
    setState(() {
      _selectionMode = nextSelectionMode;
      _selectedCount = 0;
    });
    widget.onSelectionLayoutChanged(nextSelectionMode, 0);
  }

  void _toggleAllDisplayedSelection() {
    if (_isApplying) return;
    _scrapsKey.currentState?.toggleAllDisplayedSelection();
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

  Future<void> _confirmAndMove() async {
    final scrapsState = _scrapsKey.currentState;
    final selectedCount = scrapsState?.selectedCount ?? 0;
    if (scrapsState == null || selectedCount == 0 || _isApplying) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: const Color(0xFF202020),
              title: const Text('Move scraps to Gallery?'),
              content: Text(
                'Move $selectedCount selected ${selectedCount == 1 ? 'scrap' : 'scraps'} to your Gallery?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE09321),
                  ),
                  child: const Text('Move to Gallery'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _isApplying = true);
    final result = await scrapsState.moveSelectedToGallery();
    if (!mounted) return;
    if (result.success) {
      scrapsState.clearSelection();
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
            '$selectedCount ${selectedCount == 1 ? 'scrap was' : 'scraps were'} moved to Gallery.',
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
              key: const PageStorageKey<String>('profile-scraps-scroll'),
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
                          'Scraps',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (widget.isOwnProfile)
                          IconButton(
                            key: const ValueKey(
                              'profile-scraps-selection-button',
                            ),
                            tooltip: _selectionMode
                                ? 'Cancel scrap selection'
                                : 'Select scraps to move',
                            onPressed:
                                _isApplying ? null : _toggleSelectionMode,
                            icon: Icon(
                              _selectionMode
                                  ? Icons.close
                                  : Symbols.folder_managed,
                              color: const Color(0xFFE09321),
                            ),
                          ),
                        if (widget.isOwnProfile && _selectionMode)
                          IconButton(
                            key: const ValueKey(
                              'profile-scraps-select-all-button',
                            ),
                            tooltip:
                                'Select or deselect all displayed scraps',
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
                ProfileScrapsSliver(
                  key: _scrapsKey,
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
              actionLabel: 'Move to Gallery',
              actionIcon: Icons.drive_file_move_outlined,
              destructive: false,
              isApplying: _isApplying,
              onToggleAll: _toggleAllDisplayedSelection,
              onCancel: _toggleSelectionMode,
              onApply: _confirmAndMove,
            ),
          ),
      ],
    );
  }
}
