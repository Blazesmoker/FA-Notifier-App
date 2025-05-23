// lib/utils.dart

/// Extracts the page number from the message link.
/// Example link: '/msg/pms/1/125385978/#message' -> returns 1
int extractPageNumber(String link) {
  try {
    final uri = Uri.parse(link);
    final segments = uri.pathSegments;
    if (segments.length >= 3) {
      return int.tryParse(segments[2]) ?? 1;
    }
    return 1;
  } catch (e) {
    return 1;
  }
}

/// Extracts the message ID from the message link.
/// Example link: '/msg/pms/1/125385978/#message' -> returns '125385978'
String extractMessageId(String link) {
  // 1) Classic links: /viewmessage/125385978/
  final classicMatch = RegExp(r'/viewmessage/(\d+)/').firstMatch(link);
  if (classicMatch != null) {
    return classicMatch.group(1)!;
  }

  // 2) Modern links: /msg/pms/1/125385978/
  final modernMatch = RegExp(r'/msg/pms/\d+/(\d+)/').firstMatch(link);
  if (modernMatch != null) {
    return modernMatch.group(1)!;
  }

  // fallback if no match
  return '';
}



