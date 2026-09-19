import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/shared/theme/app_theme.dart';

Widget buildSubmissionStatisticsRow({
  required int viewCount,
  required int favoritesCount,
  required int commentsCount,
  required String? rating,
}) {
  String? ratingLabel(String? r) {
    switch (r) {
      case 'general':
        return 'General';
      case 'mature':
        return 'Mature';
      case 'adult':
        return 'Adult';
      default:
        return null;
    }
  }

  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        children: [
          Text(
            '$viewCount',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Views',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      if (favoritesCount >= 0)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 5.0),
          child: Icon(Icons.circle, size: 4, color: Colors.grey),
        ),
      if (favoritesCount >= 0)
        Row(
          children: [
            Text(
              '$favoritesCount',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'Favs',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      if (favoritesCount >= 0 && commentsCount >= 0)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 5.0),
          child: Icon(Icons.circle, size: 4, color: Colors.grey),
        ),
      if (commentsCount >= 0)
        Row(
          children: [
            Text(
              '$commentsCount',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'Comments',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      if (commentsCount >= 0 && ratingLabel(rating) != null)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 5.0),
          child: Icon(Icons.circle, size: 4, color: Colors.grey),
        ),
      if (commentsCount >= 0 && ratingLabel(rating) != null)
        Tooltip(
          message: 'Rating: ${ratingLabel(rating)}',
          child: Text(
            ratingLabel(rating)!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.ratingTextColor(rating) ?? Colors.white,
            ),
          ),
        ),
    ],
  );
}
