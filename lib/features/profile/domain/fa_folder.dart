class FaFolder {
  final String name;
  final String url;

  FaFolder({required this.name, required this.url});
}

bool areFaFolderUrlsEquivalent(String url1, String url2) {
  final uri1 = Uri.parse(url1);
  final uri2 = Uri.parse(url2);

  String normalizePath(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  return uri1.scheme == uri2.scheme &&
      uri1.host == uri2.host &&
      normalizePath(uri1.path) == normalizePath(uri2.path);
}
