import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';

Widget buildJournalAuthorHeader({
  required String? profileImageUrl,
  required String? authorDisplayName,
  required String? authorUserName,
  required String? authorSymbol,
  required String? authorUserTitle,
  required bool isJournalClassic,
  required VoidCallback onAuthorTap,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (profileImageUrl != null)
        Padding(
          padding: const EdgeInsets.only(right: 8.0, top: 4.0),
          child: GestureDetector(
            onTap: onAuthorTap,
            child: FaNetworkImage(
              profileImageUrl,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return Image.asset(
                  'assets/images/defaultpic.gif',
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Image.asset(
                  'assets/images/defaultpic.gif',
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                );
              },
            ),
          ),
        ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              authorDisplayName ?? authorUserName ?? 'Anonymous',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            if (authorUserName != null && authorUserName.isNotEmpty)
              Text(
                '${(authorSymbol == null || authorSymbol.isEmpty) ? '@' : authorSymbol}$authorUserName',
                style: const TextStyle(fontSize: 11, color: Color(0xFFE09321)),
              ),
            if (!isJournalClassic && (authorUserTitle ?? '').isNotEmpty)
              Text(
                authorUserTitle!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
          ],
        ),
      ),
    ],
  );
}
