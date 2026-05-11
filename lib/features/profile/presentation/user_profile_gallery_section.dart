import 'package:flutter/material.dart';

import 'package:FANotifier/features/profile/domain/fa_folder.dart';
import 'package:FANotifier/features/profile/presentation/profilegallery.dart';

class UserProfileGallerySection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final galleryUrl = selectedFolderUrl.isNotEmpty
        ? selectedFolderUrl
        : 'https://www.furaffinity.net/gallery/$sanitizedUsername/';

    return CustomScrollView(
      slivers: [
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
                  onSelected: onFolderSelected,
                  itemBuilder: (context) {
                    return allFolders.map((folder) {
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
                      'Folder: $selectedFolderName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ProfileGallerySliver(
          username: nickname,
          selectedFolderUrl: galleryUrl,
          onFoldersParsed: onFoldersParsed,
        ),
      ],
    );
  }
}


