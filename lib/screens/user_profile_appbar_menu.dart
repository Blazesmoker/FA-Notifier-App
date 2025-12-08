import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

class ProfileAppBarMenu {
  static Future<void> showMenuAndHandle({
    required BuildContext context,
    required RelativeRect position,
    required bool isOwnProfile,
    required bool isBlocked,
    required Future<void> Function() onBlockUnblock,
    required Future<void> Function() onEdit,
    required Future<void> Function() onDelete,
    required Future<void> Function() onCopyLink,
  }) async {
    List<PopupMenuEntry<String>> menuItems = [
      const PopupMenuItem<String>(
        value: 'report',
        child: Text('Report'),
      ),
      if (!isOwnProfile)
        PopupMenuItem<String>(
          value: 'block_unblock',
          child: Text(isBlocked ? 'Unblock author' : 'Block author'),
        ),
      const PopupMenuItem<String>(
        value: 'copy_link',
        child: Text('Copy link'),
      ),
    ];

    if (isOwnProfile) {
      menuItems.add(
        const PopupMenuItem<String>(
          value: 'edit',
          child: Text('Edit'),
        ),
      );
      menuItems.add(
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(
            'Delete',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    final selected = await showMenu<String>(
      context: context,
      position: position,
      items: menuItems,
    );

    switch (selected) {
      case 'report':
        launchUrlString('https://www.furaffinity.net/controls/troubletickets/');
        break;
      case 'block_unblock':
        await onBlockUnblock();
        break;
      case 'edit':
        await onEdit();
        break;
      case 'delete':
        await onDelete();
        break;
      case 'copy_link':
        await onCopyLink();
        break;
      default:
        break;
    }
  }

  static Future<String?> showDescriptionMenu({
    required BuildContext context,
    required RelativeRect position,
  }) async {
    return showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem<String>(
          value: 'copy',
          child: Text('Copy'),
        ),
        PopupMenuItem<String>(
          value: 'select',
          child: Text('Select Text'),
        ),
      ],
    );
  }
}

