import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:FANotifier/features/profile/domain/fa_folder.dart';
import 'package:FANotifier/features/profile/domain/profile_gallery_repository.dart';
import 'package:FANotifier/features/profile/presentation/profilegallery.dart';

class UserProfileGallerySection extends StatefulWidget {
  const UserProfileGallerySection({
    super.key,
    required this.nickname,
    required this.sanitizedUsername,
    required this.selectedFolderName,
    required this.selectedFolderUrl,
    required this.allFolders,
    required this.onFolderSelected,
    required this.onFoldersParsed,
  });

  final String nickname;
  final String sanitizedUsername;
  final String selectedFolderName;
  final String selectedFolderUrl;
  final List<FaFolder> allFolders;
  final void Function(FaFolder folder) onFolderSelected;
  final void Function(List<FaFolder> folders) onFoldersParsed;

  @override
  State<UserProfileGallerySection> createState() =>
      _UserProfileGallerySectionState();
}

class _UserProfileGallerySectionState extends State<UserProfileGallerySection>
    with AutomaticKeepAliveClientMixin<UserProfileGallerySection> {
  final GlobalKey<ProfileGallerySliverState> _galleryKey =
      GlobalKey<ProfileGallerySliverState>();

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    final galleryState = _galleryKey.currentState;
    if (galleryState == null) return;
    await galleryState.refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final galleryRepository = context.read<ProfileGalleryRepository>();
    final galleryUrl = widget.selectedFolderUrl.isNotEmpty
        ? widget.selectedFolderUrl
        : galleryRepository.buildDefaultGalleryUrl(widget.sanitizedUsername);

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
                  const Text(
                    'Gallery',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PopupMenuButton<FaFolder>(
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 0),
                    onSelected: widget.onFolderSelected,
                    itemBuilder: (context) {
                      return widget.allFolders.map((folder) {
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
                      child: Text(
                        'Folder: ${widget.selectedFolderName}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
            onFoldersParsed: widget.onFoldersParsed,
          ),
        ],
      ),
    );
  }
}
