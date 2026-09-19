import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/settings/presentation/fur_affinity_settings_widgets.dart';

Widget buildEditProfileDialog({
  required BuildContext context,
}) {
  return AlertDialog(
    backgroundColor: const Color(0xFF191919),
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    actionsPadding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xFF3D3D3D)),
    ),
    title: const Text(
      'Edit Profile',
      style: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _EditProfileOption(
          icon: Icons.person_outline_rounded,
          title: 'Profile Info',
          onTap: () => Navigator.pop(context, 'profile_info'),
        ),
        const SizedBox(height: 8),
        _EditProfileOption(
          icon: Icons.panorama_outlined,
          title: 'Profile Banner',
          onTap: () => Navigator.pop(context, 'profile_banner'),
        ),
        const SizedBox(height: 8),
        _EditProfileOption(
          icon: Icons.alternate_email_rounded,
          title: 'Contacts & Social Media',
          onTap: () => Navigator.pop(context, 'contacts'),
        ),
        const SizedBox(height: 8),
        _EditProfileOption(
          icon: Icons.account_circle_outlined,
          title: 'Avatar Management',
          onTap: () => Navigator.pop(context, 'avatar'),
        ),
      ],
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
        ),
        onPressed: () => Navigator.pop(context),
        child: const Text(
          'Close',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _EditProfileOption extends StatelessWidget {
  const _EditProfileOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: furAffinitySettingsGroup,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: furAffinitySettingsDivider),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: furAffinitySettingsAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: furAffinitySettingsAccent, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF8A8A8A),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
