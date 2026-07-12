String? extractBlockUnblockKey(String urlOrPath) {
  final uri = Uri.parse(urlOrPath);
  final key = uri.queryParameters['key'];
  if (key == null || key.isEmpty) return null;
  return key;
}
