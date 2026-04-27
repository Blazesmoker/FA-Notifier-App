String extractNewestContent(String fullText) {
  const separator = '————————';
  final index = fullText.indexOf(separator);
  return index != -1 ? fullText.substring(0, index).trim() : fullText.trim();
}
