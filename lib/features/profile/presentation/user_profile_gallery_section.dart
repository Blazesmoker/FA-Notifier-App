import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:fanotifier/features/profile/domain/fa_folder.dart';
import 'package:fanotifier/features/profile/domain/profile_gallery_repository.dart';
import 'package:fanotifier/features/profile/domain/profile_folder_selection_resolver.dart';
import 'package:fanotifier/features/profile/presentation/profilegallery.dart';
import 'package:fanotifier/features/submissions/presentation/manage_submissions.dart';

class UserProfileGallerySection extends StatefulWidget {
  const UserProfileGallerySection({
    super.key,
    required this.nickname,
    required this.sanitizedUsername,
    required this.initialFolderName,
    required this.initialFolderUrl,
    required this.isOwnProfile,
    required this.detailFetchesActive,
  });

  final String nickname;
  final String sanitizedUsername;
  final String? initialFolderName;
  final String? initialFolderUrl;
  final bool isOwnProfile;
  final ValueListenable<bool> detailFetchesActive;

  @override
  State<UserProfileGallerySection> createState() =>
      _UserProfileGallerySectionState();
}

class _UserProfileGallerySectionState extends State<UserProfileGallerySection>
    with AutomaticKeepAliveClientMixin<UserProfileGallerySection> {
  final GlobalKey<ProfileGallerySliverState> _galleryKey =
      GlobalKey<ProfileGallerySliverState>();
  final ValueNotifier<int> _folderRevision = ValueNotifier<int>(0);
  late final ValueNotifier<bool> _effectiveDetailFetchesActive;
  late String _selectedFolderName;
  late String _selectedFolderUrl;
  List<FaFolder> _allFolders = <FaFolder>[];
  bool _manageSubmissionsOpen = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedFolderName = widget.initialFolderName ?? 'Main Gallery';
    _selectedFolderUrl = widget.initialFolderUrl ?? '';
    _effectiveDetailFetchesActive = ValueNotifier<bool>(
      widget.detailFetchesActive.value,
    );
    widget.detailFetchesActive.addListener(_updateDetailFetchActivity);
  }

  @override
  void didUpdateWidget(covariant UserProfileGallerySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detailFetchesActive != widget.detailFetchesActive) {
      oldWidget.detailFetchesActive
          .removeListener(_updateDetailFetchActivity);
      widget.detailFetchesActive.addListener(_updateDetailFetchActivity);
      _updateDetailFetchActivity();
    }
    if (oldWidget.sanitizedUsername != widget.sanitizedUsername ||
        oldWidget.initialFolderName != widget.initialFolderName ||
        oldWidget.initialFolderUrl != widget.initialFolderUrl) {
      _selectedFolderName = widget.initialFolderName ?? 'Main Gallery';
      _selectedFolderUrl = widget.initialFolderUrl ?? '';
      _allFolders = <FaFolder>[];
    }
  }

  @override
  void dispose() {
    widget.detailFetchesActive.removeListener(_updateDetailFetchActivity);
    _effectiveDetailFetchesActive.dispose();
    _folderRevision.dispose();
    super.dispose();
  }

  void _updateDetailFetchActivity() {
    _effectiveDetailFetchesActive.value =
        widget.detailFetchesActive.value && !_manageSubmissionsOpen;
  }

  Future<void> _refresh() async {
    final galleryState = _galleryKey.currentState;
    if (galleryState == null) return;
    await galleryState.refresh();
  }

  Future<void> _openManageSubmissions() async {
    if (_manageSubmissionsOpen) return;
    _manageSubmissionsOpen = true;
    _updateDetailFetchActivity();
    try {
      await Navigator.of(context).push(ManageSubmissionsScreen.route());
      if (!mounted) return;
      await _refresh();
    } finally {
      if (mounted) {
        _manageSubmissionsOpen = false;
        _updateDetailFetchActivity();
      }
    }
  }

  bool _foldersEqual(List<FaFolder> left, List<FaFolder> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].name != right[index].name ||
          !areFaFolderUrlsEquivalent(left[index].url, right[index].url)) {
        return false;
      }
    }
    return true;
  }

  void _onFoldersParsed(List<FaFolder> folders) {
    final selected = resolveProfileFolderSelection(
      folders: folders,
      selectedName: _selectedFolderName,
      selectedUrl: _selectedFolderUrl,
    );
    final changed = selected.name != _selectedFolderName ||
        !areFaFolderUrlsEquivalent(selected.url, _selectedFolderUrl) ||
        !_foldersEqual(folders, _allFolders);
    if (!changed) return;
    _selectedFolderName = selected.name;
    _selectedFolderUrl = selected.url;
    _allFolders = folders;
    _folderRevision.value++;
  }

  void _onFolderSelected(FaFolder folder) {
    if (folder.name == _selectedFolderName &&
        areFaFolderUrlsEquivalent(folder.url, _selectedFolderUrl)) {
      return;
    }
    _selectedFolderName = folder.name;
    _selectedFolderUrl = folder.url;
    _folderRevision.value++;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final galleryRepository = context.read<ProfileGalleryRepository>();
    return ValueListenableBuilder<int>(
      valueListenable: _folderRevision,
      builder: (context, revision, child) {
        final galleryUrl = _selectedFolderUrl.isNotEmpty
            ? _selectedFolderUrl
            : galleryRepository
                .buildDefaultGalleryUrl(widget.sanitizedUsername);
        return RefreshIndicator(
          color: const Color(0xFFE09321),
          backgroundColor: Colors.black,
          edgeOffset: 30.0,
          displacement: 85.0,
          onRefresh: _refresh,
          child: CustomScrollView(
            key: const PageStorageKey<String>('profile-gallery-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Gallery',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (widget.isOwnProfile)
                        IconButton(
                          tooltip: 'Manage submissions',
                          onPressed: _openManageSubmissions,
                          icon: const Icon(
                            Icons.settings_outlined,
                            color: Color(0xFFE09321),
                          ),
                        ),
                    ],
                  ),
                  Flexible(
                    child: PopupMenuButton<FaFolder>(
                      position: PopupMenuPosition.under,
                      offset: const Offset(0, 0),
                      onSelected: _onFolderSelected,
                      itemBuilder: (context) {
                        return _allFolders.map((folder) {
                          return PopupMenuItem<FaFolder>(
                            value: folder,
                            child: Text(folder.name),
                          );
                        }).toList();
                      },
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE09321),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFE09321),
                          disabledForegroundColor: Colors.white,
                        ),
                        onPressed: null,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Folder: $_selectedFolderName',
                            maxLines: 1,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ProfileGallerySliver(
            key: _galleryKey,
            username: widget.nickname,
            selectedFolderUrl: galleryUrl,
            onFoldersParsed: _onFoldersParsed,
            detailFetchesActive: _effectiveDetailFetchesActive,
          ),
            ],
          ),
        );
      },
    );
  }
}
