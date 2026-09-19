import 'dart:math';

import 'package:flutter_html/flutter_html.dart' as html_pkg;
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/profile/domain/shout.dart';
import 'package:fanotifier/features/profile/presentation/user_profile_styles.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

Future<bool> showProfileDeleteShoutsDialog(
  List<Shout> shoutsToDelete, {
  required BuildContext context,
  bool ownShoutOnOtherProfile = false,
}) async {
  final bool isSingle = shoutsToDelete.length == 1;
  final String title =
      isSingle ? 'Confirm deletion' : 'Delete selected shouts';
  final String message = ownShoutOnOtherProfile
      ? 'Are you sure you want to delete your shout from this profile?'
      : isSingle
          ? 'Are you sure you want to delete shout from ${shoutsToDelete.first.username}?'
          : 'Are you sure you want to delete ${shoutsToDelete.length} selected shouts?';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final maxHeight = MediaQuery.of(context).size.height * 0.55;
      final dialogHeight = isSingle ? min(maxHeight, 320.0) : maxHeight;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: shoutsToDelete.length > 2,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: shoutsToDelete.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final shout = shoutsToDelete[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F1F1F),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: FaNetworkImage(
                                    shout.avatarUrl,
                                    width: 42,
                                    height: 42,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) {
                                      return Image.asset(
                                        'assets/images/defaultpic.gif',
                                        width: 42,
                                        height: 42,
                                        fit: BoxFit.cover,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shout.username,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if ((shout.symbol?.isNotEmpty ??
                                              false) ||
                                          shout.profileNickname.isNotEmpty)
                                        Text(
                                          '${shout.symbol ?? '~'} ${shout.profileNickname}'
                                              .trim(),
                                          style: const TextStyle(
                                            color: Color(0xFFE09321),
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            html_pkg.Html(
                              data: shout.text,
                              style: userProfileHtmlStyles(),
                              extensions: buildUserProfileBBCodeExtensions(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(isSingle ? 'Delete' : 'Delete Selected'),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}
