int collapsedComposerLines(String text) {
  if (text.isEmpty) return 1;
  final lines = '\n'.allMatches(text).length + 1;
  return lines.clamp(1, 6);
}
