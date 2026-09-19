import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/presentation/widgets/submission_attachment_styles.dart';

class AttachmentFallback extends StatelessWidget {
  const AttachmentFallback({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      decoration: BoxDecoration(
        color: attachmentSurfaceColor,
        borderRadius: BorderRadius.circular(7.0),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 24.0),
          const SizedBox(width: 12.0),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13.0,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
