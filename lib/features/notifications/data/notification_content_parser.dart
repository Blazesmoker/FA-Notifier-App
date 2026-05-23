String preprocessFAEmojis(String rawHtml) {
  final exp =
      RegExp(r'<i\s+class="([^"]+)"[^>]*>(.*?)<\/i>', caseSensitive: false);
  return rawHtml.replaceAllMapped(exp, (match) {
    final classAttr = match.group(1) ?? '';
    if (classAttr.startsWith('smilie ')) {
      return '[${classAttr.replaceAll(' ', '-')}]';
    }
    return match.group(0)!;
  });
}

String stripNotificationTitledWord(String content) {
  return content.replaceAll(RegExp(r'\btitled\b', caseSensitive: false), '');
}
