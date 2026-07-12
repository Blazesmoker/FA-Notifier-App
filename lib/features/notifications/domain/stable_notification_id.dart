int stableNotificationIdFromString(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x3fffffff;
  }
  return hash == 0 ? 1 : hash;
}
