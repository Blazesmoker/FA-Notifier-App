final RegExp _faUsernameSanitizeRegex = RegExp(r'[^a-zA-Z0-9_.~-]');
final RegExp _faUsernamePrefixRegex = RegExp(r'^[~@]');

String sanitizeFAUsername(String username) {
  return username.replaceAll(_faUsernameSanitizeRegex, '').toLowerCase();
}

String normalizeFAUsernameForComparison(String? username) {
  return (username ?? '').replaceAll(_faUsernamePrefixRegex, '');
}
