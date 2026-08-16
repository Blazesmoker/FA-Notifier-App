// user_grid_section.dart

import 'package:fanotifier/features/profile/presentation/user_profile_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/fa/domain/user_link.dart';
import 'package:fanotifier/features/settings/presentation/view_list_screen.dart';

class UserGridSection extends StatelessWidget {
  final String title;
  final String viewListText;
  final int totalUsersCount;
  final List<UserLink> users;
  final String sanitizedUsername;

  const UserGridSection({
    super.key,
    required this.title,
    required this.viewListText,
    required this.totalUsersCount,
    required this.users,
    required this.sanitizedUsername,
  });

  @override
  Widget build(BuildContext context) {
    final displayUsers = users.take(6).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8.0),
            LayoutBuilder(
              builder: (context, constraints) {
                return Wrap(
                  spacing: 6.0,
                  runSpacing: 6.0,
                  children: displayUsers.map((user) {
                    final nickname = user.nickname;
                    return SizedBox(
                      width: constraints.maxWidth / 3 - 4,
                      height: 34.0,
                      child: GestureDetector(
                        onTap: () {
                          final parentState = context.findAncestorStateOfType<
                              UserProfileScreenState>();
                          parentState?.exitShoutSelectionMode();
                          Navigator.push(
                            context,
                            UserProfileScreen.route(
                              nickname: nickname,
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Color(0xFF353535),
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: 4.0, horizontal: 4.0),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                user.cleanUsername,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 8.0),
            Align(
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ViewListScreen(
                        title: title,
                        sanitizedUsername: sanitizedUsername,
                        expectedUserCount: totalUsersCount,
                      ),
                    ),
                  );
                },
                child: Text(
                  'View List ($viewListText)',
                  style: const TextStyle(
                    color: Color(0xFFE09321),
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
