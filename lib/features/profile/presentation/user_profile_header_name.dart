import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/profile/presentation/user_profile_controller.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

Widget buildProfileHeaderNameRow(GlobalKey profileNameRowKey, {
  required UserProfileController profileController,
  required VoidCallback clearProfileNameSelection,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTapDown: (TapDownDetails details) {
      final RenderBox? renderBox =
          profileNameRowKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final Offset localPosition =
            renderBox.globalToLocal(details.globalPosition);
        if (!renderBox.size.contains(localPosition)) {
          clearProfileNameSelection();
        }
      } else {
        clearProfileNameSelection();
      }
    },
    child: Container(
      key: profileNameRowKey,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (profileController.userIconBeforeUrls.isNotEmpty)
            ...profileController.userIconBeforeUrls.map(
              (url) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FaNetworkImage(url, width: 20, height: 20),
              ),
            ),
          SelectableLinkify(
            text: profileController.profileDisplayName ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
            ),
            onOpen: (link) async {},
            selectionControls: MaterialTextSelectionControls(),
          ),
          const SizedBox(width: 4),
          if (profileController.userIconAfterUrls.isNotEmpty)
            ...profileController.userIconAfterUrls.map(
              (url) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FaNetworkImage(url, width: 20, height: 20),
              ),
            ),
          SelectableLinkify(
            text: profileController.profileUserNamePart ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20.0,
            ),
            onOpen: (link) async {},
            selectionControls: MaterialTextSelectionControls(),
          ),
        ],
      ),
    ),
  );
}
